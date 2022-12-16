// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// libraries
import { LibShareUtil } from "../libraries/LibShareUtil.sol";

// interfaces
import { IMoneyMarket } from "../interfaces/IMoneyMarket.sol";
import { IAVShareToken } from "../interfaces/IAVShareToken.sol";
import { IAVHandler } from "../interfaces/IAVHandler.sol";
import { IAlpacaV2Oracle } from "../interfaces/IAlpacaV2Oracle.sol";
import { ISwapPairLike } from "../interfaces/ISwapPairLike.sol";

library LibAV01 {
  using SafeERC20 for ERC20;

  // keccak256("av.diamond.storage");
  bytes32 internal constant AV_STORAGE_POSITION = 0x7829d0c15b32d5078302aaa27ee1e42f0bdf275e05094cc17e0f59b048312982;

  enum AssetTier {
    TOKEN,
    LP
  }

  struct VaultConfig {
    uint8 leverageLevel;
    uint16 managementFeePerSec;
    address shareToken;
    address lpToken;
    address stableToken;
    address assetToken;
  }

  struct TokenConfig {
    AssetTier tier;
    uint8 to18ConversionFactor;
    uint256 maxToleranceExpiredSecond;
  }

  struct AVDiamondStorage {
    address moneyMarket;
    address oracle;
    address treasury;
    mapping(address => VaultConfig) vaultConfigs;
    mapping(address => TokenConfig) tokenConfigs;
    mapping(address => uint256) lastFeeCollectionTimestamps;
    // share token => handler
    mapping(address => address) avHandlers;
    // share token => debt token => debt value
    mapping(address => mapping(address => uint256)) vaultDebtValues;
  }

  error LibAV01_NoTinyShares();
  error LibAV01_TooLittleReceived();
  error LibAV01_InvalidHandler();
  error LibAV01_PriceStale(address _token);
  error LibAV01_UnsupportedDecimals();

  function getStorage() internal pure returns (AVDiamondStorage storage ds) {
    assembly {
      ds.slot := AV_STORAGE_POSITION
    }
  }

  /// @dev return price in 1e18
  function getPriceUSD(address _token, AVDiamondStorage storage avDs)
    internal
    view
    returns (uint256 _price, uint256 _lastUpdated)
  {
    if (avDs.tokenConfigs[_token].tier == AssetTier.LP) {
      (_price, _lastUpdated) = IAlpacaV2Oracle(avDs.oracle).lpToDollar(1e18, _token);
    } else {
      (_price, _lastUpdated) = IAlpacaV2Oracle(avDs.oracle).getTokenPrice(_token);
    }
    if (_lastUpdated < block.timestamp - avDs.tokenConfigs[_token].maxToleranceExpiredSecond)
      revert LibAV01_PriceStale(_token);
  }

  function depositToHandler(
    address _shareToken,
    address _token0,
    address _token1,
    uint256 _desiredAmount0,
    uint256 _desiredAmount1,
    uint256 _minShareOut,
    AVDiamondStorage storage avDs
  ) internal returns (uint256 _shareToMint) {
    address _handler = avDs.avHandlers[_shareToken];

    if (_handler == address(0)) revert LibAV01_InvalidHandler();

    ERC20(_token0).safeTransfer(_handler, _desiredAmount0);
    ERC20(_token1).safeTransfer(_handler, _desiredAmount1);

    uint256 _equityBefore = _getEquity(_shareToken, _handler, avDs);
    IAVHandler(_handler).onDeposit(
      _token0,
      _token1,
      _desiredAmount0,
      _desiredAmount1,
      0 // min lp amount
    );

    uint256 _equityAfter = _getEquity(_shareToken, _handler, avDs);
    uint256 _equityChanged = _equityAfter - _equityBefore;

    uint256 _totalShareTokenSupply = ERC20(_shareToken).totalSupply();

    _shareToMint = LibShareUtil.valueToShare(_equityChanged, _totalShareTokenSupply, _equityAfter);

    if (_minShareOut > _shareToMint) revert LibAV01_TooLittleReceived();

    if (_totalShareTokenSupply + _shareToMint < 10**(ERC20(_shareToken).decimals()) - 1) revert LibAV01_NoTinyShares();
  }

  function withdraw(
    address _shareToken,
    uint256 _shareAmountIn,
    uint256 _minTokenOut,
    AVDiamondStorage storage avDs
  ) internal {
    VaultConfig memory vaultConfig = avDs.vaultConfigs[_shareToken];

    // TODO: calculate amountOut with equity value
    // TODO: get token back from handler
    // TODO: handle slippage

    IAVShareToken(_shareToken).burn(msg.sender, _shareAmountIn);
    ERC20(vaultConfig.stableToken).safeTransfer(msg.sender, _minTokenOut);
  }

  function borrowMoneyMarket(
    address _shareToken,
    address _token,
    uint256 _amount,
    AVDiamondStorage storage avDs
  ) internal {
    IMoneyMarket(avDs.moneyMarket).nonCollatBorrow(_token, _amount);
    avDs.vaultDebtValues[_shareToken][_token] += _amount;
  }

  function calculateBorrowAmount(
    address _stableToken,
    address _assetToken,
    uint256 _stableDepositedAmount,
    uint8 _leverageLevel,
    LibAV01.AVDiamondStorage storage avDs
  ) internal view returns (uint256 _stableBorrowAmount, uint256 _assetBorrowAmount) {
    (uint256 _assetPrice, ) = LibAV01.getPriceUSD(_assetToken, avDs);
    (uint256 _stablePrice, ) = LibAV01.getPriceUSD(_stableToken, avDs);

    uint256 _stableTokenTo18ConversionFactor = avDs.tokenConfigs[_stableToken].to18ConversionFactor;

    uint256 _stableDepositedValue = (_stableDepositedAmount * _stableTokenTo18ConversionFactor * _stablePrice) / 1e18;
    uint256 _stableTargetValue = _stableDepositedValue * _leverageLevel;
    uint256 _stableBorrowValue = _stableTargetValue - _stableDepositedValue;

    _stableBorrowAmount = (_stableBorrowValue * 1e18) / (_stablePrice * _stableTokenTo18ConversionFactor);
    _assetBorrowAmount = (_stableTargetValue * 1e18) / (_assetPrice * _stableTokenTo18ConversionFactor);
  }

  function to18ConversionFactor(address _token) internal view returns (uint8) {
    uint256 _decimals = ERC20(_token).decimals();
    if (_decimals > 18) revert LibAV01_UnsupportedDecimals();
    uint256 _conversionFactor = 10**(18 - _decimals);
    return uint8(_conversionFactor);
  }

  function _getEquity(
    address _shareToken,
    address _handler,
    AVDiamondStorage storage avDs
  ) internal view returns (uint256 _equity) {
    VaultConfig memory _shareTokenConfig = avDs.vaultConfigs[_shareToken];
    ISwapPairLike _lpToken = ISwapPairLike(_shareTokenConfig.lpToken);
    address _token0 = _lpToken.token0();
    address _token1 = _lpToken.token1();
    uint256 _lpAmount = IAVHandler(_handler).totalLpBalance();
    if (_lpAmount > 0) {
      // get price USD
      uint256 _totalDebtValue = avDs.vaultDebtValues[_shareToken][_token0] + avDs.vaultDebtValues[_shareToken][_token1];
      _equity = _lpToValue(_lpAmount, address(_lpToken), avDs) - _totalDebtValue;
    }
  }

  /// @notice Return value of given lp amount.
  /// @param _lpAmount Amount of lp.
  function _lpToValue(
    uint256 _lpAmount,
    address _lpToken,
    AVDiamondStorage storage avDs
  ) internal view returns (uint256) {
    (uint256 _lpValue, uint256 _lastUpdated) = IAlpacaV2Oracle(avDs.oracle).lpToDollar(_lpAmount, _lpToken);
    if (block.timestamp - _lastUpdated > 86400) revert LibAV01_PriceStale(_lpToken);
    return _lpValue;
  }
}
