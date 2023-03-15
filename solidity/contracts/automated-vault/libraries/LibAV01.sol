// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// libraries
import { LibShareUtil } from "./LibShareUtil.sol";
import { LibSafeToken } from "./LibSafeToken.sol";
import { LibAVConstant } from "./LibAVConstant.sol";

// interfaces
import { IMoneyMarket } from "../interfaces/IMoneyMarket.sol";
import { IAVVaultToken } from "../interfaces/IAVVaultToken.sol";
import { IAVHandler } from "../interfaces/IAVHandler.sol";
import { IAlpacaV2Oracle } from "../interfaces/IAlpacaV2Oracle.sol";
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";
import { ISwapPairLike } from "../interfaces/ISwapPairLike.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

library LibAV01 {
  using LibSafeToken for IERC20;

  // keccak256("av.diamond.storage");
  bytes32 internal constant AV_STORAGE_POSITION = 0x7829d0c15b32d5078302aaa27ee1e42f0bdf275e05094cc17e0f59b048312982;

  event LogAccrueInterest(
    address indexed _vaultToken,
    address indexed _stableToken,
    address indexed _assetToken,
    uint256 _stableInterest,
    uint256 _assetInterest
  );

  struct AVDiamondStorage {
    address moneyMarket;
    address oracle;
    address treasury;
    uint16 repurchaseRewardBps;
    mapping(address => LibAVConstant.VaultConfig) vaultConfigs;
    mapping(address => LibAVConstant.TokenConfig) tokenConfigs;
    mapping(address => uint256) lastFeeCollectionTimestamps;
    // vault token => debt token => debt amount
    mapping(address => mapping(address => uint256)) vaultDebts;
    mapping(address => uint256) lastAccrueInterestTimestamps;
    mapping(address => bool) operatorsOk;
    mapping(address => bool) repurchasersOk;
  }

  error LibAV01_NoTinyShares();
  error LibAV01_TooLittleReceived();
  error LibAV01_InvalidHandler();
  error LibAV01_PriceStale(address _token);
  error LibAV01_UnsupportedDecimals();

  function avDiamondStorage() internal pure returns (AVDiamondStorage storage ds) {
    assembly {
      ds.slot := AV_STORAGE_POSITION
    }
  }

  function depositToHandler(
    address _handler,
    address _vaultToken,
    address _stableToken,
    address _assetToken,
    uint256 _desiredStableAmount,
    uint256 _desiredAssetAmount,
    uint256 _equityBefore,
    AVDiamondStorage storage avDs
  ) internal returns (uint256 _shareToMint) {
    IERC20(_stableToken).safeTransfer(_handler, _desiredStableAmount);
    IERC20(_assetToken).safeTransfer(_handler, _desiredAssetAmount);

    IAVHandler(_handler).onDeposit(
      _stableToken,
      _assetToken,
      _desiredStableAmount,
      _desiredAssetAmount,
      0 // min lp amount
    );

    uint256 _equityAfter = getEquity(_vaultToken, _handler, avDs);
    uint256 _equityChanged = _equityAfter - _equityBefore;

    uint256 _totalShareTokenSupply = IERC20(_vaultToken).totalSupply();

    _shareToMint = LibShareUtil.valueToShare(_equityChanged, _totalShareTokenSupply, _equityBefore);

    if (_totalShareTokenSupply + _shareToMint < 10**(IERC20(_vaultToken).decimals() - 1)) revert LibAV01_NoTinyShares();
  }

  function withdrawFromHandler(
    address _vaultToken,
    address _handler,
    uint256 _lpToWithdraw,
    AVDiamondStorage storage avDs
  ) internal returns (uint256 _stableReturnAmount, uint256 _assetReturnAmount) {
    LibAVConstant.VaultConfig memory _vaultConfig = avDs.vaultConfigs[_vaultToken];

    // (token0ReturnAmount, token1ReturnAmount)
    (_stableReturnAmount, _assetReturnAmount) = IAVHandler(_handler).onWithdraw(_lpToWithdraw);

    address _token0 = ISwapPairLike(_vaultConfig.lpToken).token0();
    if (_token0 != _vaultConfig.stableToken) {
      (_stableReturnAmount, _assetReturnAmount) = (_assetReturnAmount, _stableReturnAmount);
    }
  }

  /// @dev beware that unaccrued pendingInterest affect this calculation
  /// should call accrueInterest before calling this method to get correct value
  function getVaultTokenValueInUSD(
    address _vaultToken,
    uint256 _amount,
    AVDiamondStorage storage avDs
  ) internal view returns (uint256 _shareValue) {
    uint256 _currentEquity = getEquity(_vaultToken, avDs.vaultConfigs[_vaultToken].handler, avDs);
    uint256 _totalShareTokenSupply = IERC20(_vaultToken).totalSupply();
    _shareValue = LibShareUtil.shareToValue(_amount, _currentEquity, _totalShareTokenSupply);
  }

  /// @dev return price in 1e18
  function getPriceUSD(address _token, AVDiamondStorage storage avDs) internal view returns (uint256 _price) {
    if (avDs.tokenConfigs[_token].tier == LibAVConstant.AssetTier.LP) {
      (_price, ) = IAlpacaV2Oracle(avDs.oracle).lpToDollar(1e18, _token);
    } else {
      (_price, ) = IAlpacaV2Oracle(avDs.oracle).getTokenPrice(_token);
    }
  }

  function accrueVaultInterest(address _vaultToken, AVDiamondStorage storage avDs)
    internal
    returns (uint256 _stablePendingInterest, uint256 _assetPendingInterest)
  {
    uint256 _timeSinceLastAccrual = block.timestamp - avDs.lastAccrueInterestTimestamps[_vaultToken];

    if (_timeSinceLastAccrual > 0) {
      LibAVConstant.VaultConfig memory vaultConfig = avDs.vaultConfigs[_vaultToken];
      address _moneyMarket = avDs.moneyMarket;

      _stablePendingInterest = getTokenPendingInterest(
        _vaultToken,
        _moneyMarket,
        vaultConfig.stableToken,
        vaultConfig.stableTokenInterestModel,
        _timeSinceLastAccrual,
        avDs
      );
      _assetPendingInterest = getTokenPendingInterest(
        _vaultToken,
        _moneyMarket,
        vaultConfig.assetToken,
        vaultConfig.assetTokenInterestModel,
        _timeSinceLastAccrual,
        avDs
      );

      // update debt with interest
      avDs.vaultDebts[_vaultToken][vaultConfig.stableToken] += _stablePendingInterest;
      avDs.vaultDebts[_vaultToken][vaultConfig.assetToken] += _assetPendingInterest;

      // update timestamp
      avDs.lastAccrueInterestTimestamps[_vaultToken] = block.timestamp;

      emit LogAccrueInterest(
        _vaultToken,
        vaultConfig.stableToken,
        vaultConfig.assetToken,
        _stablePendingInterest,
        _assetPendingInterest
      );
    }
  }

  function getTokenPendingInterest(
    address _vaultToken,
    address _moneyMarket,
    address _token,
    address _interestRateModel,
    uint256 _timeSinceLastAccrual,
    AVDiamondStorage storage avDs
  ) internal view returns (uint256 _pendingInterest) {
    uint256 _debtValue = IMoneyMarket(_moneyMarket).getGlobalDebtValueWithPendingInterest(_token);
    uint256 _floating = IMoneyMarket(_moneyMarket).getFloatingBalance(_token);
    uint256 _interestRate = IInterestRateModel(_interestRateModel).getInterestRate(_debtValue, _floating);
    _pendingInterest = (_interestRate * _timeSinceLastAccrual * avDs.vaultDebts[_vaultToken][_token]) / 1e18;
  }

  function getTokenInUSD(
    address _token,
    uint256 _amount,
    AVDiamondStorage storage avDs
  ) internal view returns (uint256 _tokenValue) {
    uint256 _price = getPriceUSD(_token, avDs);
    _tokenValue = (_amount * avDs.tokenConfigs[_token].to18ConversionFactor * _price) / 1e18;
  }

  function getTokenAmountFromUSDValue(
    address _token,
    uint256 _usdValue,
    AVDiamondStorage storage avDs
  ) internal view returns (uint256 _tokenAmount) {
    _tokenAmount = ((_usdValue * 1e18) / (getPriceUSD(_token, avDs) * avDs.tokenConfigs[_token].to18ConversionFactor));
  }

  function borrowMoneyMarket(
    address _vaultToken,
    address _token,
    uint256 _amount,
    AVDiamondStorage storage avDs
  ) internal {
    IMoneyMarket(avDs.moneyMarket).nonCollatBorrow(_token, _amount);
    avDs.vaultDebts[_vaultToken][_token] += _amount;
  }

  /// @dev doesn't repay money market
  function repayVaultDebt(
    address _vaultToken,
    address _token,
    uint256 _repayAmount,
    AVDiamondStorage storage avDs
  ) internal {
    avDs.vaultDebts[_vaultToken][_token] -= _repayAmount;
  }

  function to18ConversionFactor(address _token) internal view returns (uint64) {
    uint256 _decimals = IERC20(_token).decimals();
    if (_decimals > 18) revert LibAV01_UnsupportedDecimals();
    uint256 _conversionFactor = 10**(18 - _decimals);
    return uint64(_conversionFactor);
  }

  /// @dev beware that unaccrued pendingInterest affect the result
  function getVaultTotalDebtInUSD(
    address _vaultToken,
    address _lpToken,
    AVDiamondStorage storage avDs
  ) internal view returns (uint256 _totalDebtValue) {
    address _token0 = ISwapPairLike(_lpToken).token0();
    address _token1 = ISwapPairLike(_lpToken).token1();
    _totalDebtValue =
      getTokenInUSD(_token0, avDs.vaultDebts[_vaultToken][_token0], avDs) +
      getTokenInUSD(_token1, avDs.vaultDebts[_vaultToken][_token1], avDs);
  }

  /// @dev beware that unaccrued pendingInterest affect this calculation
  /// should call accrueInterest before calling this method to get correct value
  /// @return _equity totalHandlerLPValueInUSD - stableTokenDebtValueInUSD - assetTokenDebtValueInUSD
  function getEquity(
    address _vaultToken,
    address _handler,
    AVDiamondStorage storage avDs
  ) internal view returns (uint256 _equity) {
    address _lpToken = avDs.vaultConfigs[_vaultToken].lpToken;

    uint256 _lpValue = IAVHandler(_handler).getAUMinUSD();
    uint256 _totalDebtValue = getVaultTotalDebtInUSD(_vaultToken, _lpToken, avDs);

    _equity = _lpValue > _totalDebtValue ? _lpValue - _totalDebtValue : 0;
  }

  function mintManagementFeeToTreasury(address _vaultToken, AVDiamondStorage storage avDs) internal {
    uint256 _secondsFromLastCollection = block.timestamp - avDs.lastFeeCollectionTimestamps[_vaultToken];

    if (_secondsFromLastCollection > 0) {
      uint256 _pendingManagementFee = (IAVVaultToken(_vaultToken).totalSupply() *
        avDs.vaultConfigs[_vaultToken].managementFeePerSec *
        _secondsFromLastCollection) / 1e18;

      IAVVaultToken(_vaultToken).mint(avDs.treasury, _pendingManagementFee);

      avDs.lastFeeCollectionTimestamps[_vaultToken] = block.timestamp;
    }
  }
}
