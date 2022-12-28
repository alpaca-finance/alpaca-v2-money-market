// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// libs
import { LibDoublyLinkedList } from "./LibDoublyLinkedList.sol";
import { LibFullMath } from "./LibFullMath.sol";
import { LibShareUtil } from "./LibShareUtil.sol";

// interfaces
import { IERC20 } from "../interfaces/IERC20.sol";
import { IInterestBearingToken } from "../interfaces/IInterestBearingToken.sol";
import { IAlpacaV2Oracle } from "../interfaces/IAlpacaV2Oracle.sol";
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";

library LibMoneyMarket01 {
  using LibDoublyLinkedList for LibDoublyLinkedList.List;
  using SafeCast for uint256;

  // keccak256("moneymarket.diamond.storage");
  bytes32 internal constant MONEY_MARKET_STORAGE_POSITION =
    0x2758c6926500ec9dc8ab8cea4053d172d4f50d9b78a6c2ee56aa5dd18d2c800b;

  uint256 internal constant MAX_BPS = 10000;

  error LibMoneyMarket01_BadSubAccountId();
  error LibMoneyMarket01_PriceStale(address);
  error LibMoneyMarket01_InvalidToken(address _token);
  error LibMoneyMarket01_UnsupportedDecimals();
  error LibMoneyMarket01_InvalidAssetTier();
  error LibMoneyMarket01_ExceedCollateralLimit();
  error LibMoneyMarket01_TooManyCollateralRemoved();
  error LibMoneyMarket01_BorrowingPowerTooLow();
  error LibMoneyMarket01_NotEnoughToken();
  error LibMoneyMarket01_SubAccountCallatTokenExceed();
  error LibMoneyMarket01_SubAccountOverCollatBorrowTokenExceed();
  error LibMoneyMarket01_AccountNonCollatBorrowTokenExceed();

  event LogWithdraw(address indexed _user, address _token, address _ibToken, uint256 _amountIn, uint256 _amountOut);
  event LogAccrueInterest(address indexed _token, uint256 _totalInterest, uint256 _totalToProtocolReserve);

  enum AssetTier {
    UNLISTED,
    ISOLATE,
    CROSS,
    COLLATERAL
  }

  struct TokenConfig {
    LibMoneyMarket01.AssetTier tier;
    uint8 to18ConversionFactor;
    uint16 collateralFactor;
    uint16 borrowingFactor;
    uint256 maxCollateral;
    uint256 maxBorrow; // shared global limit
  }

  struct ProtocolConfig {
    mapping(address => uint256) maxTokenBorrow; // token limit per account
    uint256 borrowLimitUSDValue;
  }

  // Storage
  struct MoneyMarketDiamondStorage {
    address nativeToken;
    address nativeRelayer;
    address treasury;
    // ibToken implementation
    address ibTokenImplementation;
    IAlpacaV2Oracle oracle;
    mapping(address => address) tokenToIbTokens;
    mapping(address => address) ibTokenToTokens;
    mapping(address => uint256) overCollatDebtValues;
    mapping(address => uint256) overCollatDebtShares;
    mapping(address => uint256) globalDebts;
    mapping(address => uint256) collats;
    mapping(address => LibDoublyLinkedList.List) subAccountCollats;
    mapping(address => LibDoublyLinkedList.List) subAccountDebtShares;
    // account -> list token debt
    mapping(address => LibDoublyLinkedList.List) nonCollatAccountDebtValues;
    // token -> debt of each account
    mapping(address => LibDoublyLinkedList.List) nonCollatTokenDebtValues;
    // account -> ProtocolConfig
    mapping(address => ProtocolConfig) protocolConfigs;
    mapping(address => bool) nonCollatBorrowerOk;
    mapping(address => TokenConfig) tokenConfigs;
    mapping(address => uint256) debtLastAccrueTime;
    mapping(address => IInterestRateModel) interestModels;
    mapping(bytes32 => IInterestRateModel) nonCollatInterestModels;
    mapping(address => bool) repurchasersOk;
    mapping(address => bool) liquidationStratOk;
    mapping(address => bool) liquidatorsOk;
    // reserve pool
    mapping(address => uint256) protocolReserves;
    // diamond token balances
    mapping(address => uint256) reserves;
    uint8 maxNumOfCollatPerSubAccount;
    uint8 maxNumOfDebtPerSubAccount;
    uint8 maxNumOfDebtPerNonCollatAccount;
    // liquidation factor
    uint16 maxLiquidateBps;
    uint16 liquidationThresholdBps;
    // fees
    uint16 lendingFeeBps;
    uint16 repurchaseRewardBps;
    uint16 repurchaseFeeBps;
    uint16 liquidationFeeBps;
    uint256 maxPriceStale;
  }

  function moneyMarketDiamondStorage() internal pure returns (MoneyMarketDiamondStorage storage moneyMarketStorage) {
    assembly {
      moneyMarketStorage.slot := MONEY_MARKET_STORAGE_POSITION
    }
  }

  function getSubAccount(address primary, uint256 subAccountId) internal pure returns (address) {
    if (subAccountId > 255) revert LibMoneyMarket01_BadSubAccountId();
    return address(uint160(primary) ^ uint160(subAccountId));
  }

  function getTotalBorrowingPower(address _subAccount, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _totalBorrowingPowerUSDValue)
  {
    LibDoublyLinkedList.Node[] memory _collats = moneyMarketDs.subAccountCollats[_subAccount].getAll();

    address _collatToken;
    address _underlyingToken;
    uint256 _tokenPrice;
    TokenConfig memory _tokenConfig;

    uint256 _collatsLength = _collats.length;

    for (uint256 _i; _i < _collatsLength; ) {
      _collatToken = _collats[_i].token;

      (_tokenPrice, ) = getPriceUSD(_collatToken, moneyMarketDs);

      _underlyingToken = moneyMarketDs.ibTokenToTokens[_collatToken];
      _tokenConfig = moneyMarketDs.tokenConfigs[_underlyingToken == address(0) ? _collatToken : _underlyingToken];

      // _totalBorrowingPowerUSDValue += amount * tokenPrice * collateralFactor
      _totalBorrowingPowerUSDValue += LibFullMath.mulDiv(
        _collats[_i].amount * _tokenConfig.to18ConversionFactor * _tokenConfig.collateralFactor,
        _tokenPrice,
        1e22
      );

      unchecked {
        ++_i;
      }
    }
  }

  function getNonCollatTokenDebt(address _token, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _totalNonCollatDebt)
  {
    LibDoublyLinkedList.Node[] memory _nonCollatDebts = moneyMarketDs.nonCollatTokenDebtValues[_token].getAll();

    uint256 _length = _nonCollatDebts.length;

    for (uint256 _i; _i < _length; ) {
      _totalNonCollatDebt += _nonCollatDebts[_i].amount;

      unchecked {
        ++_i;
      }
    }
  }

  function getTotalUsedBorrowingPower(address _subAccount, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _totalUsedBorrowingPower, bool _hasIsolateAsset)
  {
    LibDoublyLinkedList.Node[] memory _borrowed = moneyMarketDs.subAccountDebtShares[_subAccount].getAll();

    uint256 _borrowedLength = _borrowed.length;

    for (uint256 _i; _i < _borrowedLength; ) {
      TokenConfig memory _tokenConfig = moneyMarketDs.tokenConfigs[_borrowed[_i].token];

      if (_tokenConfig.tier == LibMoneyMarket01.AssetTier.ISOLATE) {
        _hasIsolateAsset = true;
      }

      (uint256 _tokenPrice, ) = getPriceUSD(_borrowed[_i].token, moneyMarketDs);

      uint256 _borrowedAmount = LibShareUtil.shareToValue(
        _borrowed[_i].amount,
        moneyMarketDs.overCollatDebtValues[_borrowed[_i].token],
        moneyMarketDs.overCollatDebtShares[_borrowed[_i].token]
      );

      _totalUsedBorrowingPower += usedBorrowingPower(_borrowedAmount, _tokenPrice, _tokenConfig.borrowingFactor);

      unchecked {
        ++_i;
      }
    }
  }

  function getTotalNonCollatUsedBorrowingPower(address _account, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _totalUsedBorrowingPower, bool _hasIsolateAsset)
  {
    LibDoublyLinkedList.Node[] memory _borrowed = moneyMarketDs.nonCollatAccountDebtValues[_account].getAll();

    uint256 _borrowedLength = _borrowed.length;

    for (uint256 _i = 0; _i < _borrowedLength; ) {
      TokenConfig memory _tokenConfig = moneyMarketDs.tokenConfigs[_borrowed[_i].token];

      if (_tokenConfig.tier == LibMoneyMarket01.AssetTier.ISOLATE) {
        _hasIsolateAsset = true;
      }

      (uint256 _tokenPrice, ) = getPriceUSD(_borrowed[_i].token, moneyMarketDs);

      _totalUsedBorrowingPower += usedBorrowingPower(_borrowed[_i].amount, _tokenPrice, _tokenConfig.borrowingFactor);

      unchecked {
        ++_i;
      }
    }
  }

  function getTotalBorrowedUSDValue(address _subAccount, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _totalBorrowedUSDValue)
  {
    LibDoublyLinkedList.Node[] memory _borrowed = moneyMarketDs.subAccountDebtShares[_subAccount].getAll();

    uint256 _borrowedLength = _borrowed.length;

    for (uint256 _i; _i < _borrowedLength; ) {
      (uint256 _tokenPrice, ) = getPriceUSD(_borrowed[_i].token, moneyMarketDs);
      uint256 _borrowedAmount = LibShareUtil.shareToValue(
        _borrowed[_i].amount,
        moneyMarketDs.overCollatDebtValues[_borrowed[_i].token],
        moneyMarketDs.overCollatDebtShares[_borrowed[_i].token]
      );

      TokenConfig memory _tokenConfig = moneyMarketDs.tokenConfigs[_borrowed[_i].token];
      // _totalBorrowedUSDValue += _borrowedAmount * tokenPrice
      _totalBorrowedUSDValue += LibFullMath.mulDiv(
        _borrowedAmount * _tokenConfig.to18ConversionFactor,
        _tokenPrice,
        1e18
      );

      unchecked {
        ++_i;
      }
    }
  }

  // _usedBorrowingPower += _borrowedAmount * tokenPrice * (10000/ borrowingFactor)
  function usedBorrowingPower(
    uint256 _borrowedAmount,
    uint256 _tokenPrice,
    uint256 _borrowingFactor
  ) internal pure returns (uint256 _usedBorrowingPower) {
    _usedBorrowingPower = LibFullMath.mulDiv(_borrowedAmount * MAX_BPS, _tokenPrice, 1e18 * uint256(_borrowingFactor));
  }

  function getGlobalPendingInterest(address _token, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _globalPendingInterest)
  {
    uint256 _lastAccrueTime = moneyMarketDs.debtLastAccrueTime[_token];
    if (block.timestamp > _lastAccrueTime) {
      uint256 _timePast = block.timestamp - _lastAccrueTime;

      // over collat interest
      if (address(moneyMarketDs.interestModels[_token]) == address(0)) {
        return 0;
      }

      uint256 _interestRatePerSec = getOverCollatInterestRate(_token, moneyMarketDs);

      _globalPendingInterest = (_interestRatePerSec * _timePast * moneyMarketDs.overCollatDebtValues[_token]) / 1e18;

      // non collat interest
      LibDoublyLinkedList.Node[] memory _borrowedAccounts = moneyMarketDs.nonCollatTokenDebtValues[_token].getAll();
      uint256 _accountLength = _borrowedAccounts.length;
      for (uint256 _i; _i < _accountLength; ) {
        address _account = _borrowedAccounts[_i].token;

        uint256 _nonCollatInterestRate = getNonCollatInterestRate(_account, _token, moneyMarketDs);

        _globalPendingInterest += (_nonCollatInterestRate * _timePast * _borrowedAccounts[_i].amount) / 1e18;

        unchecked {
          ++_i;
        }
      }
    }
  }

  function getOverCollatInterestRate(address _token, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256)
  {
    address _interestModel = address(moneyMarketDs.interestModels[_token]);
    if (_interestModel == address(0)) {
      return 0;
    }
    uint256 _debtValue = moneyMarketDs.globalDebts[_token];
    uint256 _floating = getFloatingBalance(_token, moneyMarketDs);
    return IInterestRateModel(_interestModel).getInterestRate(_debtValue, _floating);
  }

  function getNonCollatInterestRate(
    address _account,
    address _token,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256) {
    bytes32 _nonCollatId = getNonCollatId(_account, _token);
    address _interestModel = address(moneyMarketDs.nonCollatInterestModels[_nonCollatId]);
    if (_interestModel == address(0)) {
      return 0;
    }
    uint256 _debtValue = moneyMarketDs.globalDebts[_token];
    uint256 _floating = getFloatingBalance(_token, moneyMarketDs);
    return IInterestRateModel(_interestModel).getInterestRate(_debtValue, _floating);
  }

  function accrueOverCollatInterest(
    address _token,
    uint256 _timePast,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal returns (uint256 _overCollatInterest) {
    _overCollatInterest =
      (getOverCollatInterestRate(_token, moneyMarketDs) * _timePast * moneyMarketDs.overCollatDebtValues[_token]) /
      1e18;
    // update overcollat debt
    moneyMarketDs.overCollatDebtValues[_token] += _overCollatInterest;
  }

  function accrueInterest(address _token, MoneyMarketDiamondStorage storage moneyMarketDs) internal {
    uint256 _lastAccrueTime = moneyMarketDs.debtLastAccrueTime[_token];
    if (block.timestamp > _lastAccrueTime) {
      uint256 _timePast = block.timestamp - _lastAccrueTime;

      uint256 _overCollatInterest = accrueOverCollatInterest(_token, _timePast, moneyMarketDs);
      uint256 _totalNonCollatInterest = accrueNonCollatInterest(_token, _timePast, moneyMarketDs);

      // update global debt
      uint256 _totalInterest = (_overCollatInterest + _totalNonCollatInterest);
      moneyMarketDs.globalDebts[_token] += _totalInterest;

      // update timestamp
      moneyMarketDs.debtLastAccrueTime[_token] = block.timestamp;

      // book protocol's revenue
      uint256 _protocolFee = (_totalInterest * moneyMarketDs.lendingFeeBps) / MAX_BPS;
      moneyMarketDs.protocolReserves[_token] += (_totalInterest * moneyMarketDs.lendingFeeBps) / MAX_BPS;

      emit LogAccrueInterest(_token, _totalInterest, _protocolFee);
    }
  }

  function accrueNonCollatInterest(
    address _token,
    uint256 _timePast,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal returns (uint256 _totalNonCollatInterest) {
    LibDoublyLinkedList.Node[] memory _borrowedAccounts = moneyMarketDs.nonCollatTokenDebtValues[_token].getAll();
    uint256 _accountLength = _borrowedAccounts.length;
    address _account;
    uint256 _currentAccountDebt;
    uint256 _accountInterest;
    uint256 _newNonCollatDebtValue;

    for (uint256 _i; _i < _accountLength; ) {
      _account = _borrowedAccounts[_i].token;
      _currentAccountDebt = _borrowedAccounts[_i].amount;

      _accountInterest =
        (getNonCollatInterestRate(_account, _token, moneyMarketDs) * _timePast * _currentAccountDebt) /
        1e18;
      {
        // update non collat debt states
        _newNonCollatDebtValue = _currentAccountDebt + _accountInterest;
        // 1. account debt
        moneyMarketDs.nonCollatAccountDebtValues[_account].updateOrRemove(_token, _newNonCollatDebtValue);

        // 2. token debt
        moneyMarketDs.nonCollatTokenDebtValues[_token].updateOrRemove(_account, _newNonCollatDebtValue);
      }

      _totalNonCollatInterest += _accountInterest;
      unchecked {
        ++_i;
      }
    }
  }

  function accrueBorrowedPositionsOf(address _subAccount, MoneyMarketDiamondStorage storage moneyMarketDs) internal {
    LibDoublyLinkedList.Node[] memory _borrowed = moneyMarketDs.subAccountDebtShares[_subAccount].getAll();

    uint256 _borrowedLength = _borrowed.length;

    for (uint256 _i; _i < _borrowedLength; ) {
      accrueInterest(_borrowed[_i].token, moneyMarketDs);
      unchecked {
        ++_i;
      }
    }
  }

  function accrueNonCollatBorrowedPositionsOf(address _account, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
  {
    LibDoublyLinkedList.Node[] memory _borrowed = moneyMarketDs.nonCollatAccountDebtValues[_account].getAll();

    uint256 _borrowedLength = _borrowed.length;

    for (uint256 _i = 0; _i < _borrowedLength; ) {
      accrueInterest(_borrowed[_i].token, moneyMarketDs);
      unchecked {
        ++_i;
      }
    }
  }

  // totalToken is the amount of token remains in ((MM + borrowed amount)
  // - (protocol's reserve pool)
  // where borrowed amount consists of over-collat and non-collat borrowing
  function getTotalToken(address _token, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256)
  {
    return
      (moneyMarketDs.reserves[_token] + moneyMarketDs.globalDebts[_token]) - (moneyMarketDs.protocolReserves[_token]);
  }

  function getTotalTokenWithPendingInterest(address _token, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256)
  {
    return
      getTotalToken(_token, moneyMarketDs) +
      ((getGlobalPendingInterest(_token, moneyMarketDs) * moneyMarketDs.lendingFeeBps) / LibMoneyMarket01.MAX_BPS);
  }

  function getFloatingBalance(address _token, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _floating)
  {
    _floating = moneyMarketDs.reserves[_token];
  }

  function setIbPair(
    address _token,
    address _ibToken,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    moneyMarketDs.tokenToIbTokens[_token] = _ibToken;
    moneyMarketDs.ibTokenToTokens[_ibToken] = _token;
  }

  function setTokenConfig(
    address _token,
    TokenConfig memory _config,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    moneyMarketDs.tokenConfigs[_token] = _config;
  }

  function getPriceUSD(address _token, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _price, uint256 _lastUpdated)
  {
    address _underlyingToken = moneyMarketDs.ibTokenToTokens[_token];
    // If the token is ibToken, do an additional shareToValue before pricing
    if (_underlyingToken != address(0)) {
      uint256 _underlyingTokenPrice;
      (_underlyingTokenPrice, _lastUpdated) = moneyMarketDs.oracle.getTokenPrice(_underlyingToken);

      uint256 _totalSupply = IERC20(_token).totalSupply();
      uint256 _totalToken = getTotalTokenWithPendingInterest(_underlyingToken, moneyMarketDs);

      _price = LibShareUtil.shareToValue(_underlyingTokenPrice, _totalToken, _totalSupply);
    } else {
      (_price, _lastUpdated) = moneyMarketDs.oracle.getTokenPrice(_token);
    }

    if (_lastUpdated < block.timestamp - moneyMarketDs.maxPriceStale) revert LibMoneyMarket01_PriceStale(_token);
  }

  function getNonCollatId(address _account, address _token) internal pure returns (bytes32 _id) {
    _id = keccak256(abi.encodePacked(_account, _token));
  }

  function withdraw(
    address _ibToken,
    uint256 _shareAmount,
    address _withdrawFrom,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal returns (address _token, uint256 _shareValue) {
    _token = moneyMarketDs.ibTokenToTokens[_ibToken];
    accrueInterest(_token, moneyMarketDs);

    if (_token == address(0)) {
      revert LibMoneyMarket01_InvalidToken(_ibToken);
    }

    _shareValue = LibShareUtil.shareToValue(
      _shareAmount,
      getTotalToken(_token, moneyMarketDs),
      IERC20(_ibToken).totalSupply()
    );

    if (_shareValue > moneyMarketDs.reserves[_token]) revert LibMoneyMarket01_NotEnoughToken();
    moneyMarketDs.reserves[_token] -= _shareValue;

    IInterestBearingToken(_ibToken).onWithdraw(_withdrawFrom, _withdrawFrom, _shareValue, _shareAmount);

    emit LogWithdraw(_withdrawFrom, _token, _ibToken, _shareAmount, _shareValue);
  }

  function to18ConversionFactor(address _token) internal view returns (uint8) {
    uint256 _decimals = IERC20(_token).decimals();
    if (_decimals > 18) revert LibMoneyMarket01_UnsupportedDecimals();
    uint256 _conversionFactor = 10**(18 - _decimals);
    return uint8(_conversionFactor);
  }

  function addCollat(
    address _subAccount,
    address _token,
    uint256 _addAmount,
    MoneyMarketDiamondStorage storage ds
  ) internal {
    // validation
    if (ds.tokenConfigs[_token].tier != AssetTier.COLLATERAL) revert LibMoneyMarket01_InvalidAssetTier();
    if (_addAmount + ds.collats[_token] > ds.tokenConfigs[_token].maxCollateral)
      revert LibMoneyMarket01_ExceedCollateralLimit();

    // init list
    LibDoublyLinkedList.List storage subAccountCollateralList = ds.subAccountCollats[_subAccount];
    if (subAccountCollateralList.getNextOf(LibDoublyLinkedList.START) == LibDoublyLinkedList.EMPTY) {
      subAccountCollateralList.init();
    }

    uint256 _currentCollatAmount = subAccountCollateralList.getAmount(_token);
    // update state
    subAccountCollateralList.addOrUpdate(_token, _currentCollatAmount + _addAmount);
    if (subAccountCollateralList.length() > ds.maxNumOfCollatPerSubAccount)
      revert LibMoneyMarket01_SubAccountCallatTokenExceed();
    ds.collats[_token] += _addAmount;
  }

  function removeCollat(
    address _subAccount,
    address _token,
    uint256 _removeAmount,
    MoneyMarketDiamondStorage storage ds
  ) internal {
    removeCollatFromSubAccount(_subAccount, _token, _removeAmount, ds);

    ds.collats[_token] -= _removeAmount;
  }

  function removeCollatFromSubAccount(
    address _subAccount,
    address _token,
    uint256 _removeAmount,
    MoneyMarketDiamondStorage storage ds
  ) internal {
    LibDoublyLinkedList.List storage _subAccountCollatList = ds.subAccountCollats[_subAccount];
    uint256 _currentCollatAmount = _subAccountCollatList.getAmount(_token);
    if (_removeAmount > _currentCollatAmount) {
      revert LibMoneyMarket01_TooManyCollateralRemoved();
    }
    _subAccountCollatList.updateOrRemove(_token, _currentCollatAmount - _removeAmount);

    uint256 _totalBorrowingPower = getTotalBorrowingPower(_subAccount, ds);
    (uint256 _totalUsedBorrowingPower, ) = getTotalUsedBorrowingPower(_subAccount, ds);
    // violate check-effect pattern for gas optimization, will change after come up with a way that doesn't loop
    if (_totalBorrowingPower < _totalUsedBorrowingPower) {
      revert LibMoneyMarket01_BorrowingPowerTooLow();
    }
  }

  function transferCollat(
    address _toSubAccount,
    address _token,
    uint256 _transferAmount,
    MoneyMarketDiamondStorage storage ds
  ) internal {
    LibDoublyLinkedList.List storage toSubAccountCollateralList = ds.subAccountCollats[_toSubAccount];
    if (toSubAccountCollateralList.getNextOf(LibDoublyLinkedList.START) == LibDoublyLinkedList.EMPTY) {
      toSubAccountCollateralList.init();
    }
    uint256 _currentCollatAmount = toSubAccountCollateralList.getAmount(_token);
    toSubAccountCollateralList.addOrUpdate(_token, _currentCollatAmount + _transferAmount);
    if (toSubAccountCollateralList.length() > ds.maxNumOfCollatPerSubAccount)
      revert LibMoneyMarket01_SubAccountCallatTokenExceed();
  }

  function getOverCollatDebt(
    address _subAccount,
    address _token,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _debtShare, uint256 _debtAmount) {
    _debtShare = moneyMarketDs.subAccountDebtShares[_subAccount].getAmount(_token);

    // Note: precision loss 1 wei when convert share back to value
    _debtAmount = LibShareUtil.shareToValue(
      _debtShare,
      moneyMarketDs.overCollatDebtValues[_token],
      moneyMarketDs.overCollatDebtShares[_token]
    );
  }

  function getNonCollatDebt(
    address _account,
    address _token,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _debtAmount) {
    _debtAmount = moneyMarketDs.nonCollatAccountDebtValues[_account].getAmount(_token);
  }

  function getShareAmountFromValue(
    address _underlyingToken,
    address _ibToken,
    uint256 _value,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _totalSupply, uint256 _ibShareAmount) {
    _totalSupply = IInterestBearingToken(_ibToken).totalSupply();
    uint256 _totalToken = LibMoneyMarket01.getTotalToken(_underlyingToken, moneyMarketDs);
    _ibShareAmount = LibShareUtil.valueToShare(_value, _totalSupply, _totalToken);
  }

  function overCollatBorrow(
    address _subAccount,
    address _token,
    uint256 _amount,
    MoneyMarketDiamondStorage storage ds
  ) internal returns (uint256 _shareToAdd) {
    LibDoublyLinkedList.List storage userDebtShare = ds.subAccountDebtShares[_subAccount];

    if (userDebtShare.getNextOf(LibDoublyLinkedList.START) == LibDoublyLinkedList.EMPTY) {
      userDebtShare.init();
    }

    _shareToAdd = LibShareUtil.valueToShareRoundingUp(
      _amount,
      ds.overCollatDebtShares[_token],
      ds.overCollatDebtValues[_token]
    );

    // update over collat debt
    ds.overCollatDebtShares[_token] += _shareToAdd;
    ds.overCollatDebtValues[_token] += _amount;

    // update global debt
    ds.globalDebts[_token] += _amount;

    // update user's debtshare
    userDebtShare.addOrUpdate(_token, userDebtShare.getAmount(_token) + _shareToAdd);
    if (userDebtShare.length() > ds.maxNumOfDebtPerSubAccount)
      revert LibMoneyMarket01_SubAccountOverCollatBorrowTokenExceed();

    // update facet token balance
    ds.reserves[_token] -= _amount;
  }

  function nonCollatBorrow(
    address _account,
    address _token,
    uint256 _amount,
    MoneyMarketDiamondStorage storage ds
  ) internal {
    LibDoublyLinkedList.List storage debtValue = ds.nonCollatAccountDebtValues[_account];

    if (debtValue.getNextOf(LibDoublyLinkedList.START) == LibDoublyLinkedList.EMPTY) {
      debtValue.init();
    }

    LibDoublyLinkedList.List storage tokenDebts = ds.nonCollatTokenDebtValues[_token];

    if (tokenDebts.getNextOf(LibDoublyLinkedList.START) == LibDoublyLinkedList.EMPTY) {
      tokenDebts.init();
    }

    // update account debt
    uint256 _newAccountDebt = debtValue.getAmount(_token) + _amount;
    uint256 _newTokenDebt = tokenDebts.getAmount(msg.sender) + _amount;

    debtValue.addOrUpdate(_token, _newAccountDebt);

    if (debtValue.length() > ds.maxNumOfDebtPerNonCollatAccount)
      revert LibMoneyMarket01_AccountNonCollatBorrowTokenExceed();

    tokenDebts.addOrUpdate(msg.sender, _newTokenDebt);

    // update global debt

    ds.globalDebts[_token] += _amount;
  }
}
