// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// libraries
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";

// interfaces
import { IMoneyMarket } from "../interfaces/IMoneyMarket.sol";
import { IAVShareToken } from "../interfaces/IAVShareToken.sol";
import { IAVHandler } from "../interfaces/IAVHandler.sol";
import { IAlpacaV2Oracle } from "../interfaces/IAlpacaV2Oracle.sol";
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";
import { ISwapPairLike } from "../interfaces/ISwapPairLike.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

import "solidity/tests/utils/console.sol";

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
    address stableTokenInterestModel;
    address assetTokenInterestModel;
    address handler;
  }

  struct TokenConfig {
    AssetTier tier;
    uint64 to18ConversionFactor;
  }

  struct AVDiamondStorage {
    address moneyMarket;
    address oracle;
    address treasury;
    mapping(address => VaultConfig) vaultConfigs;
    mapping(address => TokenConfig) tokenConfigs;
    mapping(address => uint256) lastFeeCollectionTimestamps;
    // vault token => debt token => debt amount
    mapping(address => mapping(address => uint256)) vaultDebts;
    mapping(address => uint256) lastAccrueInterestTimestamps;
    mapping(address => bool) rebalancerOk;
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
    address _shareToken,
    address _token0,
    address _token1,
    uint256 _desiredAmount0,
    uint256 _desiredAmount1,
    uint256 _equityBefore,
    AVDiamondStorage storage avDs
  ) internal returns (uint256 _shareToMint) {
    IERC20(_token0).safeTransfer(_handler, _desiredAmount0);
    IERC20(_token1).safeTransfer(_handler, _desiredAmount1);

    IAVHandler(_handler).onDeposit(
      _token0,
      _token1,
      _desiredAmount0,
      _desiredAmount1,
      0 // min lp amount
    );

    uint256 _equityAfter = getEquity(_shareToken, _handler, avDs);
    uint256 _equityChanged = _equityAfter - _equityBefore;

    uint256 _totalShareTokenSupply = IERC20(_shareToken).totalSupply();

    _shareToMint = LibShareUtil.valueToShare(_equityChanged, _totalShareTokenSupply, _equityBefore);

    if (_totalShareTokenSupply + _shareToMint < 10**(IERC20(_shareToken).decimals() - 1)) revert LibAV01_NoTinyShares();
  }

  function withdrawFromHandler(
    address _vaultToken,
    address _handler,
    uint256 _lpToWithdraw,
    AVDiamondStorage storage avDs
  ) internal returns (uint256 _stableReturnAmount, uint256 _assetReturnAmount) {
    VaultConfig memory _vaultConfig = avDs.vaultConfigs[_vaultToken];

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
    if (avDs.tokenConfigs[_token].tier == AssetTier.LP) {
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
      VaultConfig memory vaultConfig = avDs.vaultConfigs[_vaultToken];
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

  function usdToTokenAmount(
    address _token,
    uint256 _usdValue,
    AVDiamondStorage storage avDs
  ) internal view returns (uint256 _tokenAmount) {
    _tokenAmount = ((_usdValue * 1e18) / (getPriceUSD(_token, avDs) * avDs.tokenConfigs[_token].to18ConversionFactor));
  }

  function borrowMoneyMarket(
    address _shareToken,
    address _token,
    uint256 _amount,
    AVDiamondStorage storage avDs
  ) internal {
    IMoneyMarket(avDs.moneyMarket).nonCollatBorrow(_token, _amount);
    avDs.vaultDebts[_shareToken][_token] += _amount;
  }

  function repayVaultDebt(
    address _shareToken,
    address _token,
    uint256 _repayAmount,
    AVDiamondStorage storage avDs
  ) internal {
    // IERC20(_token).safeIncreaseAllowance(avDs.moneyMarket, _repayAmount);
    // IMoneyMarket(avDs.moneyMarket).nonCollatRepay(address(this), _token, _repayAmount);
    avDs.vaultDebts[_shareToken][_token] -= _repayAmount;
  }

  function calculateBorrowAmount(
    address _stableToken,
    address _assetToken,
    uint256 _stableDepositedAmount,
    uint8 _leverageLevel,
    LibAV01.AVDiamondStorage storage avDs
  ) internal view returns (uint256 _stableBorrowAmount, uint256 _assetBorrowAmount) {
    uint256 _stablePrice = getPriceUSD(_stableToken, avDs);
    uint256 _assetPrice = getPriceUSD(_assetToken, avDs);

    uint256 _stableTokenTo18ConversionFactor = avDs.tokenConfigs[_stableToken].to18ConversionFactor;

    uint256 _stableDepositedValue = (_stableDepositedAmount * _stableTokenTo18ConversionFactor * _stablePrice) / 1e18;
    uint256 _targetBorrowValue = _stableDepositedValue * _leverageLevel;

    uint256 _stableBorrowValue = _targetBorrowValue / 2;
    uint256 _assetBorrowValue = _targetBorrowValue - _stableBorrowValue;

    _stableBorrowAmount =
      ((_stableBorrowValue - _stableDepositedValue) * 1e18) /
      (_stablePrice * _stableTokenTo18ConversionFactor);
    _assetBorrowAmount =
      (_assetBorrowValue * 1e18) /
      (_assetPrice * avDs.tokenConfigs[_assetToken].to18ConversionFactor);
  }

  function to18ConversionFactor(address _token) internal view returns (uint64) {
    uint256 _decimals = IERC20(_token).decimals();
    if (_decimals > 18) revert LibAV01_UnsupportedDecimals();
    uint256 _conversionFactor = 10**(18 - _decimals);
    return uint64(_conversionFactor);
  }

  function getHandlerTotalLPValueInUSD(
    address _handler,
    address _lpToken,
    AVDiamondStorage storage avDs
  ) internal view returns (uint256 _totalLPValueUSD) {
    uint256 _lpAmount = IAVHandler(_handler).totalLpBalance();
    _totalLPValueUSD = getTokenInUSD(_lpToken, _lpAmount, avDs);
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

    uint256 _lpValue = getHandlerTotalLPValueInUSD(_handler, _lpToken, avDs);
    uint256 _totalDebtValue = getVaultTotalDebtInUSD(_vaultToken, _lpToken, avDs);

    console.log("_lpValue", _lpValue);
    console.log("_totalDebtValue", _totalDebtValue);

    _equity = _lpValue > _totalDebtValue ? _lpValue - _totalDebtValue : 0;
  }

  function getPendingManagementFee(address _shareToken, AVDiamondStorage storage avDs)
    public
    view
    returns (uint256 _pendingManagementFee)
  {
    uint256 _secondsFromLastCollection = block.timestamp - avDs.lastFeeCollectionTimestamps[_shareToken];
    _pendingManagementFee =
      (IERC20(_shareToken).totalSupply() *
        avDs.vaultConfigs[_shareToken].managementFeePerSec *
        _secondsFromLastCollection) /
      1e18;
  }

  function mintManagementFeeToTreasury(address _vaultToken, LibAV01.AVDiamondStorage storage avDs) internal {
    IAVShareToken(_vaultToken).mint(avDs.treasury, getPendingManagementFee(_vaultToken, avDs));
    avDs.lastFeeCollectionTimestamps[_vaultToken] = block.timestamp;
  }
}
