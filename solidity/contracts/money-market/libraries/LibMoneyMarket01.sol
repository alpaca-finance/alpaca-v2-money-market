// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// libs
import { LibDoublyLinkedList } from "./LibDoublyLinkedList.sol";
import { LibFullMath } from "./LibFullMath.sol";
import { LibShareUtil } from "./LibShareUtil.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";

// interfaces
import { IERC20 } from "../interfaces/IERC20.sol";
import { IInterestBearingToken } from "../interfaces/IInterestBearingToken.sol";
import { IAlpacaV2Oracle } from "../interfaces/IAlpacaV2Oracle.sol";
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";
import { IFeeModel } from "../interfaces/IFeeModel.sol";
import { IMiniFL } from "../interfaces/IMiniFL.sol";
import { IDebtToken } from "../interfaces/IDebtToken.sol";

library LibMoneyMarket01 {
  using LibDoublyLinkedList for LibDoublyLinkedList.List;
  using SafeCast for uint256;
  using LibSafeToken for IERC20;

  // keccak256("moneymarket.diamond.storage");
  bytes32 internal constant MONEY_MARKET_STORAGE_POSITION =
    0x2758c6926500ec9dc8ab8cea4053d172d4f50d9b78a6c2ee56aa5dd18d2c800b;

  uint256 internal constant MAX_BPS = 10000;
  uint256 internal constant MAX_REPURCHASE_FEE_BPS = 1000;

  error LibMoneyMarket01_BadSubAccountId();
  error LibMoneyMarket01_InvalidToken(address _token);
  error LibMoneyMarket01_UnsupportedDecimals();
  error LibMoneyMarket01_InvalidAssetTier();
  error LibMoneyMarket01_ExceedCollateralLimit();
  error LibMoneyMarket01_TooManyCollateralRemoved();
  error LibMoneyMarket01_BorrowingPowerTooLow();
  error LibMoneyMarket01_NotEnoughToken();
  error LibMoneyMarket01_NumberOfTokenExceedLimit();
  error LibMoneyMarket01_FeeOnTransferTokensNotSupported();
  error LibMoneyMarket01_EmergencyPaused();

  event LogWithdraw(address indexed _user, address _token, address _ibToken, uint256 _amountIn, uint256 _amountOut);
  event LogAccrueInterest(address indexed _token, uint256 _totalInterest, uint256 _totalToProtocolReserve);
  event LogRemoveDebt(
    address indexed _subAccount,
    address indexed _token,
    uint256 _removedDebtShare,
    uint256 _removedDebtAmount
  );

  event LogRemoveCollateral(address indexed _subAccount, address indexed _token, uint256 _amount);

  event LogAddCollateral(address indexed _subAccount, address indexed _token, address _caller, uint256 _amount);

  enum AssetTier {
    UNLISTED,
    ISOLATE,
    CROSS,
    COLLATERAL
  }

  struct TokenConfig {
    LibMoneyMarket01.AssetTier tier;
    uint16 collateralFactor;
    uint16 borrowingFactor;
    uint64 to18ConversionFactor;
    uint256 maxCollateral;
    uint256 maxBorrow; // shared global limit
  }

  struct ProtocolConfig {
    mapping(address => uint256) maxTokenBorrow; // token limit per account
    uint256 borrowLimitUSDValue;
  }

  // Storage
  struct MoneyMarketDiamondStorage {
    // ---- addresses ---- //
    address wNativeToken;
    address wNativeRelayer;
    address liquidationTreasury;
    address ibTokenImplementation;
    address debtTokenImplementation;
    IAlpacaV2Oracle oracle;
    IFeeModel repurchaseRewardModel;
    IMiniFL miniFL;
    bool emergencyPaused; // flag for pausing deposit and borrow on moeny market
    // ---- ib tokens ---- //
    mapping(address => address) tokenToIbTokens; // token address => ibToken address
    mapping(address => address) ibTokenToTokens; // ibToken address => token address
    // ---- debt tokens ---- //
    mapping(address => address) tokenToDebtTokens; // token address => debtToken address
    // ---- miniFL pools ---- //
    mapping(address => uint256) miniFLPoolIds; // token address => pool id
    // ---- lending ---- //
    mapping(address => uint256) globalDebts; // token address => over + non collat debt
    // ---- over-collateralized lending ---- //
    mapping(address => uint256) overCollatDebtValues; // borrower address => debt amount in borrowed token
    mapping(address => uint256) overCollatDebtShares; // borrower address => debt shares
    mapping(address => uint256) collats; // token address => total collateral of a token
    mapping(address => IInterestRateModel) interestModels; // token address => over-collat interest model
    // ---- non-collateralized lending ---- //
    mapping(address => LibDoublyLinkedList.List) nonCollatAccountDebtValues; // account => list token debt
    mapping(address => LibDoublyLinkedList.List) nonCollatTokenDebtValues; // token => debt of each account
    mapping(address => ProtocolConfig) protocolConfigs; // account => ProtocolConfig
    mapping(address => mapping(address => IInterestRateModel)) nonCollatInterestModels; // [account][token] => non-collat interest model
    mapping(address => bool) nonCollatBorrowerOk; // can this address do non collat borrow
    // ---- subAccounts ---- //
    mapping(address => LibDoublyLinkedList.List) subAccountCollats; // subAccount => list of subAccount's all collateral
    mapping(address => LibDoublyLinkedList.List) subAccountDebtShares; // subAccount => list of subAccount's all debt
    // ---- tokens ---- //
    mapping(address => TokenConfig) tokenConfigs; // token address => config
    mapping(address => uint256) debtLastAccruedAt; // token address => last interest accrual timestamp, shared between over and non collat
    // ---- whitelists ---- //
    mapping(address => bool) repurchasersOk; // is this address allowed to repurchase
    mapping(address => bool) liquidationStratOk; // liquidation strategies that can be used during liquidation process
    mapping(address => bool) liquidatorsOk; // allowed to initiate liquidation process
    // ---- reserves ---- //
    mapping(address => uint256) protocolReserves; // token address => amount that is reserved for protocol
    mapping(address => uint256) reserves; // token address => amount that is available in protocol
    // ---- protocol params ---- //
    uint256 minDebtSize; // minimum debt that borrower must maintain
    // maximum number of token in the linked list
    uint8 maxNumOfCollatPerSubAccount;
    uint8 maxNumOfDebtPerSubAccount;
    uint8 maxNumOfDebtPerNonCollatAccount;
    // liquidation params
    uint16 maxLiquidateBps; // maximum portion of debt that is allowed to be repurchased / liquidated per transaction
    uint16 liquidationThresholdBps; // threshold that allow subAccount to be liquidated if borrowing power goes below threshold
    // fees
    uint16 lendingFeeBps; // fee that is charged from lending interest by protocol, goes to protocolReserve
    uint16 repurchaseFeeBps; // fee that is charged during repurchase by protocol, goes to liquidationTreasury
    uint16 liquidationFeeBps; // fee that is charged during liquidation by protocol, goes to liquidationTreasury
    uint16 liquidationRewardBps; // reward that is given to liquidators
  }

  function moneyMarketDiamondStorage() internal pure returns (MoneyMarketDiamondStorage storage moneyMarketStorage) {
    assembly {
      moneyMarketStorage.slot := MONEY_MARKET_STORAGE_POSITION
    }
  }

  function getSubAccount(address primary, uint256 subAccountId) internal pure returns (address) {
    if (subAccountId > 255) {
      revert LibMoneyMarket01_BadSubAccountId();
    }
    return address(uint160(primary) ^ uint160(subAccountId));
  }

  function getTotalBorrowingPower(address _subAccount, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _totalBorrowingPower)
  {
    LibDoublyLinkedList.Node[] memory _collats = moneyMarketDs.subAccountCollats[_subAccount].getAll();

    address _collatToken;
    address _underlyingToken;
    uint256 _tokenPrice;
    TokenConfig memory _tokenConfig;

    uint256 _collatsLength = _collats.length;

    for (uint256 _i; _i < _collatsLength; ) {
      _collatToken = _collats[_i].token;

      _tokenPrice = getPriceUSD(_collatToken, moneyMarketDs);

      _underlyingToken = moneyMarketDs.ibTokenToTokens[_collatToken];
      _tokenConfig = moneyMarketDs.tokenConfigs[_underlyingToken == address(0) ? _collatToken : _underlyingToken];

      // _totalBorrowingPower += amount * tokenPrice * collateralFactor
      _totalBorrowingPower += LibFullMath.mulDiv(
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

    address _borrowedToken;
    TokenConfig memory _tokenConfig;

    for (uint256 _i; _i < _borrowedLength; ) {
      _borrowedToken = _borrowed[_i].token;
      _tokenConfig = moneyMarketDs.tokenConfigs[_borrowedToken];

      if (_tokenConfig.tier == LibMoneyMarket01.AssetTier.ISOLATE) {
        _hasIsolateAsset = true;
      }

      _totalUsedBorrowingPower += usedBorrowingPower(
        LibShareUtil.shareToValue(
          _borrowed[_i].amount,
          moneyMarketDs.overCollatDebtValues[_borrowedToken],
          moneyMarketDs.overCollatDebtShares[_borrowedToken]
        ),
        getPriceUSD(_borrowedToken, moneyMarketDs),
        _tokenConfig.borrowingFactor,
        _tokenConfig.to18ConversionFactor
      );

      unchecked {
        ++_i;
      }
    }
  }

  function getTotalNonCollatUsedBorrowingPower(address _account, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _totalUsedBorrowingPower)
  {
    LibDoublyLinkedList.Node[] memory _borrowed = moneyMarketDs.nonCollatAccountDebtValues[_account].getAll();

    uint256 _borrowedLength = _borrowed.length;

    TokenConfig memory _tokenConfig;
    address _borrowedToken;

    for (uint256 _i; _i < _borrowedLength; ) {
      _borrowedToken = _borrowed[_i].token;
      _tokenConfig = moneyMarketDs.tokenConfigs[_borrowedToken];

      _totalUsedBorrowingPower += usedBorrowingPower(
        _borrowed[_i].amount,
        getPriceUSD(_borrowedToken, moneyMarketDs),
        _tokenConfig.borrowingFactor,
        _tokenConfig.to18ConversionFactor
      );

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

    address _borrowedToken;
    uint256 _borrowedAmount;

    for (uint256 _i; _i < _borrowedLength; ) {
      _borrowedToken = _borrowed[_i].token;

      _borrowedAmount = LibShareUtil.shareToValue(
        _borrowed[_i].amount,
        moneyMarketDs.overCollatDebtValues[_borrowedToken],
        moneyMarketDs.overCollatDebtShares[_borrowedToken]
      );

      // _totalBorrowedUSDValue += _borrowedAmount * tokenPrice
      _totalBorrowedUSDValue += LibFullMath.mulDiv(
        _borrowedAmount * moneyMarketDs.tokenConfigs[_borrowedToken].to18ConversionFactor,
        getPriceUSD(_borrowedToken, moneyMarketDs),
        1e18
      );

      unchecked {
        ++_i;
      }
    }
  }

  /// @dev usedBorrowingPower = borrowedAmountE18 * tokenPrice * (MAX_BPS / borrowingFactor)
  function usedBorrowingPower(
    uint256 _borrowedAmount,
    uint256 _tokenPrice,
    uint256 _borrowingFactor,
    uint256 _to18ConversionFactor
  ) internal pure returns (uint256 _usedBorrowingPower) {
    _usedBorrowingPower = LibFullMath.mulDiv(
      _borrowedAmount * _to18ConversionFactor,
      _tokenPrice,
      1e14 * _borrowingFactor // gas savings: 1e14 = 1e18 / MAX_BPS
    );
  }

  function getGlobalPendingInterest(address _token, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _globalPendingInterest)
  {
    uint256 _lastAccrualTimestamp = moneyMarketDs.debtLastAccruedAt[_token];

    if (block.timestamp > _lastAccrualTimestamp) {
      uint256 _secondsSinceLastAccrual;
      unchecked {
        _secondsSinceLastAccrual = block.timestamp - _lastAccrualTimestamp;
      }
      LibDoublyLinkedList.Node[] memory _borrowedAccounts = moneyMarketDs.nonCollatTokenDebtValues[_token].getAll();
      uint256 _accountLength = _borrowedAccounts.length;
      uint256 _nonCollatInterestPerSec;
      for (uint256 _i; _i < _accountLength; ) {
        _nonCollatInterestPerSec += (getNonCollatInterestRate(_borrowedAccounts[_i].token, _token, moneyMarketDs) *
          _borrowedAccounts[_i].amount);

        unchecked {
          ++_i;
        }
      }

      // _globalPendingInterest = (nonCollatInterestAmountPerSec + overCollatInterestAmountPerSec) * _secondsSinceLastAccrual
      _globalPendingInterest =
        ((_nonCollatInterestPerSec +
          (getOverCollatInterestRate(_token, moneyMarketDs) * moneyMarketDs.overCollatDebtValues[_token])) *
          _secondsSinceLastAccrual) /
        1e18;
    }
  }

  function getOverCollatInterestRate(address _token, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _interestRate)
  {
    IInterestRateModel _interestModel = moneyMarketDs.interestModels[_token];
    if (address(_interestModel) == address(0)) {
      return 0;
    }
    _interestRate = _interestModel.getInterestRate(
      moneyMarketDs.globalDebts[_token],
      getFloatingBalance(_token, moneyMarketDs)
    );
  }

  function getNonCollatInterestRate(
    address _account,
    address _token,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _interestRate) {
    IInterestRateModel _interestModel = moneyMarketDs.nonCollatInterestModels[_account][_token];
    if (address(_interestModel) == address(0)) {
      return 0;
    }
    _interestRate = _interestModel.getInterestRate(
      moneyMarketDs.globalDebts[_token],
      getFloatingBalance(_token, moneyMarketDs)
    );
  }

  function accrueOverCollatInterest(
    address _token,
    uint256 _timePast,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal returns (uint256 _overCollatInterest) {
    // cache to save gas
    uint256 _totalDebtValue = moneyMarketDs.overCollatDebtValues[_token];
    _overCollatInterest = (getOverCollatInterestRate(_token, moneyMarketDs) * _timePast * _totalDebtValue) / 1e18;

    // update overcollat debt
    moneyMarketDs.overCollatDebtValues[_token] = _totalDebtValue + _overCollatInterest;
  }

  function accrueInterest(address _token, MoneyMarketDiamondStorage storage moneyMarketDs) internal {
    uint256 _lastAccrualTimestamp = moneyMarketDs.debtLastAccruedAt[_token];
    if (block.timestamp > _lastAccrualTimestamp) {
      uint256 _secondsSinceLastAccrual;
      unchecked {
        _secondsSinceLastAccrual = block.timestamp - _lastAccrualTimestamp;
      }
      uint256 _overCollatInterest = accrueOverCollatInterest(_token, _secondsSinceLastAccrual, moneyMarketDs);
      uint256 _nonCollatInterest = accrueNonCollatInterest(_token, _secondsSinceLastAccrual, moneyMarketDs);

      // update global debt
      uint256 _totalInterest = _overCollatInterest + _nonCollatInterest;
      moneyMarketDs.globalDebts[_token] += _totalInterest;

      // update timestamp
      moneyMarketDs.debtLastAccruedAt[_token] = block.timestamp;

      // book protocol's revenue
      uint256 _protocolFee = (_totalInterest * moneyMarketDs.lendingFeeBps) / MAX_BPS;
      moneyMarketDs.protocolReserves[_token] += _protocolFee;

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

      // update non collat debt states
      _newNonCollatDebtValue = _currentAccountDebt + _accountInterest;
      // 1. account debt
      moneyMarketDs.nonCollatAccountDebtValues[_account].addOrUpdate(_token, _newNonCollatDebtValue);
      // 2. token debt
      moneyMarketDs.nonCollatTokenDebtValues[_token].addOrUpdate(_account, _newNonCollatDebtValue);

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

    for (uint256 _i; _i < _borrowedLength; ) {
      accrueInterest(_borrowed[_i].token, moneyMarketDs);
      unchecked {
        ++_i;
      }
    }
  }

  /// @dev totalToken = amount of token remains in MM + debt - protocol reserve
  /// where debt consists of over-collat and non-collat
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
      ((getGlobalPendingInterest(_token, moneyMarketDs) * (LibMoneyMarket01.MAX_BPS - moneyMarketDs.lendingFeeBps)) /
        LibMoneyMarket01.MAX_BPS);
  }

  function getFloatingBalance(address _token, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _floating)
  {
    _floating = moneyMarketDs.reserves[_token];
  }

  function getPriceUSD(address _token, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _price)
  {
    address _underlyingToken = moneyMarketDs.ibTokenToTokens[_token];
    // If the token is ibToken, do an additional shareToValue before pricing
    if (_underlyingToken != address(0)) {
      uint256 _underlyingTokenPrice;
      (_underlyingTokenPrice, ) = moneyMarketDs.oracle.getTokenPrice(_underlyingToken);
      // TODO: optimize this
      uint256 _totalSupply = IERC20(_token).totalSupply();
      uint256 _totalToken = getTotalTokenWithPendingInterest(_underlyingToken, moneyMarketDs);

      _price = LibShareUtil.shareToValue(_underlyingTokenPrice, _totalToken, _totalSupply);
    } else {
      (_price, ) = moneyMarketDs.oracle.getTokenPrice(_token);
    }
  }

  /// @dev must accrue interest for underlying token before withdraw
  function withdraw(
    address _underlyingToken,
    address _ibToken,
    uint256 _shareAmount,
    address _withdrawFrom,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal returns (uint256 _withdrawAmount) {
    _withdrawAmount = LibShareUtil.shareToValue(
      _shareAmount,
      getTotalToken(_underlyingToken, moneyMarketDs), // ok to use getTotalToken here because we need to call accrueInterest before withdraw
      IERC20(_ibToken).totalSupply()
    );

    if (_withdrawAmount > moneyMarketDs.reserves[_underlyingToken]) {
      revert LibMoneyMarket01_NotEnoughToken();
    }

    // burn ibToken
    IInterestBearingToken(_ibToken).onWithdraw(_withdrawFrom, _withdrawFrom, _withdrawAmount, _shareAmount);

    emit LogWithdraw(_withdrawFrom, _underlyingToken, _ibToken, _shareAmount, _withdrawAmount);
  }

  function to18ConversionFactor(address _token) internal view returns (uint64) {
    uint256 _decimals = IERC20(_token).decimals();
    if (_decimals > 18) {
      revert LibMoneyMarket01_UnsupportedDecimals();
    }
    uint256 _conversionFactor = 10**(18 - _decimals);
    return uint64(_conversionFactor);
  }

  function addCollatToSubAccount(
    address _subAccount,
    address _token,
    uint256 _addAmount,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    // validation
    if (moneyMarketDs.tokenConfigs[_token].tier != AssetTier.COLLATERAL) {
      revert LibMoneyMarket01_InvalidAssetTier();
    }
    if (_addAmount + moneyMarketDs.collats[_token] > moneyMarketDs.tokenConfigs[_token].maxCollateral) {
      revert LibMoneyMarket01_ExceedCollateralLimit();
    }

    // init list
    LibDoublyLinkedList.List storage subAccountCollateralList = moneyMarketDs.subAccountCollats[_subAccount];
    subAccountCollateralList.initIfNotExist();

    // TODO: optimize this
    uint256 _currentCollatAmount = subAccountCollateralList.getAmount(_token);
    // update state
    subAccountCollateralList.addOrUpdate(_token, _currentCollatAmount + _addAmount);
    if (subAccountCollateralList.length() > moneyMarketDs.maxNumOfCollatPerSubAccount) {
      revert LibMoneyMarket01_NumberOfTokenExceedLimit();
    }
    moneyMarketDs.collats[_token] += _addAmount;

    // stake token to miniFL, when user add collateral by ibToken
    uint256 _poolId = moneyMarketDs.miniFLPoolIds[_token];
    IMiniFL _miniFL = moneyMarketDs.miniFL;
    if (_poolId != 0) {
      IERC20(_token).safeIncreaseAllowance(address(_miniFL), _addAmount);
      _miniFL.deposit(_subAccount, _poolId, _addAmount);
    }

    emit LogAddCollateral(_subAccount, _token, msg.sender, _addAmount);
  }

  function removeCollatFromSubAccount(
    address _subAccount,
    address _token,
    uint256 _removeAmount,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    LibDoublyLinkedList.List storage _subAccountCollatList = moneyMarketDs.subAccountCollats[_subAccount];
    uint256 _currentCollatAmount = _subAccountCollatList.getAmount(_token);
    if (_removeAmount > _currentCollatAmount) {
      revert LibMoneyMarket01_TooManyCollateralRemoved();
    }
    _subAccountCollatList.updateOrRemove(_token, _currentCollatAmount - _removeAmount);
    moneyMarketDs.collats[_token] -= _removeAmount;

    // withdraw token from miniFL
    uint256 _poolId = moneyMarketDs.miniFLPoolIds[_token];
    if (_poolId != 0) {
      moneyMarketDs.miniFL.withdraw(_subAccount, _poolId, _removeAmount);
    }

    emit LogRemoveCollateral(_subAccount, _token, _removeAmount);
  }

  function validateSubaccountIsHealthy(address _subAccount, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
  {
    uint256 _totalBorrowingPower = getTotalBorrowingPower(_subAccount, moneyMarketDs);
    (uint256 _totalUsedBorrowingPower, ) = getTotalUsedBorrowingPower(_subAccount, moneyMarketDs);
    if (_totalBorrowingPower < _totalUsedBorrowingPower) {
      revert LibMoneyMarket01_BorrowingPowerTooLow();
    }
  }

  function removeOverCollatDebtFromSubAccount(
    address _account,
    address _subAccount,
    address _repayToken,
    uint256 _debtShareToRemove,
    uint256 _debtValueToRemove,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    uint256 _currentDebtShare = moneyMarketDs.subAccountDebtShares[_subAccount].getAmount(_repayToken);

    moneyMarketDs.subAccountDebtShares[_subAccount].updateOrRemove(_repayToken, _currentDebtShare - _debtShareToRemove);
    moneyMarketDs.overCollatDebtShares[_repayToken] -= _debtShareToRemove;
    moneyMarketDs.overCollatDebtValues[_repayToken] -= _debtValueToRemove;

    moneyMarketDs.globalDebts[_repayToken] -= _debtValueToRemove;

    // withdraw debt token from miniFL
    // Note: prevent stack too deep
    moneyMarketDs.miniFL.withdraw(
      _account,
      moneyMarketDs.miniFLPoolIds[moneyMarketDs.tokenToDebtTokens[_repayToken]],
      _debtShareToRemove
    );

    // burn debt token
    IDebtToken(moneyMarketDs.tokenToDebtTokens[_repayToken]).burn(address(this), _debtShareToRemove);

    // withdraw token from miniFL
    uint256 _poolId = moneyMarketDs.miniFLPoolIds[_repayToken];
    if (_poolId != 0) {
      moneyMarketDs.miniFL.withdraw(_subAccount, _poolId, _debtShareToRemove);
    }

    emit LogRemoveDebt(_subAccount, _repayToken, _debtShareToRemove, _debtValueToRemove);
  }

  function transferCollat(
    address _toSubAccount,
    address _token,
    uint256 _transferAmount,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    LibDoublyLinkedList.List storage toSubAccountCollateralList = moneyMarketDs.subAccountCollats[_toSubAccount];
    toSubAccountCollateralList.initIfNotExist();
    uint256 _currentCollatAmount = toSubAccountCollateralList.getAmount(_token);
    toSubAccountCollateralList.addOrUpdate(_token, _currentCollatAmount + _transferAmount);
    if (toSubAccountCollateralList.length() > moneyMarketDs.maxNumOfCollatPerSubAccount) {
      revert LibMoneyMarket01_NumberOfTokenExceedLimit();
    }
  }

  function getOverCollatDebtShareAndAmountOf(
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
    uint256 _totalToken = LibMoneyMarket01.getTotalTokenWithPendingInterest(_underlyingToken, moneyMarketDs);
    _ibShareAmount = LibShareUtil.valueToShare(_value, _totalSupply, _totalToken);
  }

  function overCollatBorrow(
    address _account,
    address _subAccount,
    address _token,
    uint256 _amount,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal returns (uint256 _shareToAdd) {
    LibDoublyLinkedList.List storage userDebtShare = moneyMarketDs.subAccountDebtShares[_subAccount];
    IMiniFL _miniFL = moneyMarketDs.miniFL;

    userDebtShare.initIfNotExist();

    _shareToAdd = LibShareUtil.valueToShareRoundingUp(
      _amount,
      moneyMarketDs.overCollatDebtShares[_token],
      moneyMarketDs.overCollatDebtValues[_token]
    );

    // update over collat debt
    moneyMarketDs.overCollatDebtShares[_token] += _shareToAdd;
    moneyMarketDs.overCollatDebtValues[_token] += _amount;

    // update global debt
    moneyMarketDs.globalDebts[_token] += _amount;

    // update user's debtshare
    userDebtShare.addOrUpdate(_token, userDebtShare.getAmount(_token) + _shareToAdd);
    if (userDebtShare.length() > moneyMarketDs.maxNumOfDebtPerSubAccount) {
      revert LibMoneyMarket01_NumberOfTokenExceedLimit();
    }

    // mint debt token to money market and stake to miniFL
    address _debtToken = moneyMarketDs.tokenToDebtTokens[_token];
    uint256 _poolId = moneyMarketDs.miniFLPoolIds[_debtToken];

    IDebtToken(_debtToken).mint(address(this), _amount);
    IERC20(_debtToken).safeIncreaseAllowance(address(_miniFL), _amount);
    _miniFL.deposit(_account, _poolId, _amount);
  }

  function nonCollatBorrow(
    address _account,
    address _token,
    uint256 _amount,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    LibDoublyLinkedList.List storage debtValue = moneyMarketDs.nonCollatAccountDebtValues[_account];
    debtValue.initIfNotExist();

    LibDoublyLinkedList.List storage tokenDebts = moneyMarketDs.nonCollatTokenDebtValues[_token];
    tokenDebts.initIfNotExist();

    // update account debt
    uint256 _newAccountDebt = debtValue.getAmount(_token) + _amount;
    uint256 _newTokenDebt = tokenDebts.getAmount(msg.sender) + _amount;

    debtValue.addOrUpdate(_token, _newAccountDebt);

    if (debtValue.length() > moneyMarketDs.maxNumOfDebtPerNonCollatAccount) {
      revert LibMoneyMarket01_NumberOfTokenExceedLimit();
    }

    tokenDebts.addOrUpdate(msg.sender, _newTokenDebt);

    // update global debt
    moneyMarketDs.globalDebts[_token] += _amount;
  }

  /// @dev safeTransferFrom that revert when not receiving full amount (have fee on transfer)
  function pullExactTokens(
    address _token,
    address _from,
    uint256 _amount
  ) internal {
    uint256 _balanceBefore = IERC20(_token).balanceOf(address(this));
    IERC20(_token).safeTransferFrom(_from, address(this), _amount);
    if (IERC20(_token).balanceOf(address(this)) - _balanceBefore != _amount) {
      revert LibMoneyMarket01_FeeOnTransferTokensNotSupported();
    }
  }

  /// @dev safeTransferFrom that return actual amount received
  function unsafePullTokens(
    address _token,
    address _from,
    uint256 _amount
  ) internal returns (uint256 _actualAmountReceived) {
    uint256 _balanceBefore = IERC20(_token).balanceOf(address(this));
    IERC20(_token).safeTransferFrom(_from, address(this), _amount);
    _actualAmountReceived = IERC20(_token).balanceOf(address(this)) - _balanceBefore;
  }

  function onlyLive(MoneyMarketDiamondStorage storage moneyMarketDs) internal view {
    if (moneyMarketDs.emergencyPaused) {
      revert LibMoneyMarket01_EmergencyPaused();
    }
  }
}
