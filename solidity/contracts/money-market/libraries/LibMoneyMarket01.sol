// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// libs
import { LibDoublyLinkedList } from "./LibDoublyLinkedList.sol";
import { LibFullMath } from "./LibFullMath.sol";
import { LibShareUtil } from "./LibShareUtil.sol";
import { LibConstant } from "./LibConstant.sol";
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
  error LibMoneyMarket01_UnAuthorized();
  error LibMoneyMarket01_SubAccountHealthy();

  event LogWithdraw(address indexed _user, address _token, address _ibToken, uint256 _amountIn, uint256 _amountOut);
  event LogAccrueInterest(address indexed _token, uint256 _totalInterest, uint256 _totalToProtocolReserve);
  event LogRemoveDebt(
    address indexed _account,
    address indexed _subAccount,
    address indexed _token,
    uint256 _removedDebtShare,
    uint256 _removedDebtAmount,
    uint256 _numOfDebt
  );

  event LogRemoveCollateral(
    address indexed _account,
    address indexed _subAccount,
    address indexed _token,
    uint256 _amount
  );

  event LogAddCollateral(
    address indexed _account,
    address indexed _subAccount,
    address indexed _token,
    address _caller,
    uint256 _amount
  );

  event LogOverCollatBorrow(
    address indexed _account,
    address indexed _subAccount,
    address indexed _token,
    uint256 _borrowedAmount,
    uint256 _debtShare,
    uint256 _numOfDebt
  );

  event LogWriteOffSubAccountDebt(
    address indexed subAccount,
    address indexed token,
    uint256 debtShareWrittenOff,
    uint256 debtValueWrittenOff
  );

  struct ProtocolConfig {
    mapping(address => uint256) maxTokenBorrow; // token limit per account
    uint256 borrowingPowerLimit;
  }

  // Storage
  struct MoneyMarketDiamondStorage {
    // ---- addresses ---- //
    address liquidationTreasury;
    address ibTokenImplementation;
    address debtTokenImplementation;
    IAlpacaV2Oracle oracle;
    IFeeModel repurchaseRewardModel;
    IMiniFL miniFL;
    bool emergencyPaused; // flag for pausing deposit and borrow on the money market
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
    mapping(address => LibConstant.TokenConfig) tokenConfigs; // token address => config
    mapping(address => uint256) debtLastAccruedAt; // token address => last interest accrual timestamp, shared between over and non collat
    // ---- whitelists ---- //
    mapping(address => bool) liquidationStratOk; // liquidation strategies that can be used during liquidation process
    mapping(address => bool) liquidatorsOk; // allowed to initiate liquidation process
    mapping(address => bool) accountManagersOk; // allowed to manipulate account/subaccount on behalf of end users
    // ---- reserves ---- //
    mapping(address => uint256) protocolReserves; // token address => amount that is reserved for protocol
    mapping(address => uint256) reserves; // token address => amount that is available in protocol
    // ---- protocol params ---- //
    uint256 minDebtSize; // minimum debt that borrower must maintain
    // maximum number of token in the linked list
    uint8 maxNumOfCollatPerSubAccount;
    uint8 maxNumOfDebtPerSubAccount;
    uint8 maxNumOfDebtPerNonCollatAccount;
    // counting of non collat borrowers
    uint8 countNonCollatBorrowers;
    // liquidation params
    uint16 maxLiquidateBps; // maximum portion of debt that is allowed to be repurchased / liquidated per transaction
    uint16 liquidationThresholdBps; // threshold that allow subAccount to be liquidated if borrowing power goes below threshold
    // fees
    uint16 lendingFeeBps; // fee that is charged from lending interest by protocol, goes to protocolReserve
    uint16 repurchaseFeeBps; // fee that is charged during repurchase by protocol, goes to liquidationTreasury
    uint16 liquidationFeeBps; // fee that is charged during liquidation by protocol, goes to liquidationTreasury
  }

  /// @dev Get money market storage
  /// @return moneyMarketStorage The storage of money market
  function moneyMarketDiamondStorage() internal pure returns (MoneyMarketDiamondStorage storage moneyMarketStorage) {
    assembly {
      moneyMarketStorage.slot := MONEY_MARKET_STORAGE_POSITION
    }
  }

  /// @dev Calculate sub account address
  /// @param primary The account address
  /// @param subAccountId A sub account id
  /// @return The sub account address
  function getSubAccount(address primary, uint256 subAccountId) internal pure returns (address) {
    // revert if subAccountId is greater than 255
    if (subAccountId > 255) {
      revert LibMoneyMarket01_BadSubAccountId();
    }
    // sub account address is the XOR of primary address and subAccountId
    // primary address is 20 bytes long, so it is (20 * 8) = 160 bits long
    //
    // calculation:
    // sub account address = primary XOR subAccountId
    //
    // example:
    //  - primary           = 0x0...88
    //  - subAccountId      = 2
    //
    //  sub account address = 0x0...88 XOR 2
    //                      = 0x0...8a
    return address(uint160(primary) ^ uint160(subAccountId));
  }

  /// @dev Calculate total borrowing power of a sub account
  /// @param _subAccount The sub account address
  /// @param moneyMarketDs The storage of money market
  /// @return _totalBorrowingPower The total borrowing power of a sub account
  function getTotalBorrowingPower(address _subAccount, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _totalBorrowingPower)
  {
    // get all collats of a sub account
    LibDoublyLinkedList.Node[] memory _collats = moneyMarketDs.subAccountCollats[_subAccount].getAll();

    address _collatToken;
    uint256 _tokenPrice;
    LibConstant.TokenConfig memory _tokenConfig;

    uint256 _collatsLength = _collats.length;

    // sum up total borrowing power
    for (uint256 _i; _i < _collatsLength; ) {
      _collatToken = _collats[_i].token;

      // get collat token price in USD
      _tokenPrice = getPriceUSD(_collatToken, moneyMarketDs);
      _tokenConfig = moneyMarketDs.tokenConfigs[_collatToken];

      // calulation:
      // _totalBorrowingPower += amount * tokenPrice * collateralFactor
      //
      // example:
      //  - amount                = 100
      //  - tokenPrice            = 1
      //  - collateralFactor      = 9000 (need to divide by LibConstant.MAX_BPS)
      //
      //  _totalBorrowingPower   += 100 * 1 * (9000/10000)
      //                         += 90
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

  /// @dev Calculate total non collat token debt of a token
  /// @param _token The token address
  /// @param moneyMarketDs The storage of money market
  /// @return _totalNonCollatDebt The total non collat token debt
  function getNonCollatTokenDebt(address _token, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _totalNonCollatDebt)
  {
    // get all non collat token debt values of _token
    LibDoublyLinkedList.Node[] memory _nonCollatDebts = moneyMarketDs.nonCollatTokenDebtValues[_token].getAll();

    uint256 _length = _nonCollatDebts.length;

    // sum up total non collat token debt of _token
    for (uint256 _i; _i < _length; ) {
      _totalNonCollatDebt += _nonCollatDebts[_i].amount;

      unchecked {
        ++_i;
      }
    }
  }

  /// @dev Calculate total used borrowing power of a sub account
  /// @param _subAccount The sub account address
  /// @param moneyMarketDs The storage of money market
  /// @return _totalUsedBorrowingPower The total used borrowing power of a sub account
  /// @return _hasIsolateAsset True if sub account has isolate asset
  function getTotalUsedBorrowingPower(address _subAccount, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _totalUsedBorrowingPower, bool _hasIsolateAsset)
  {
    // get all borrowed positions of a sub account
    LibDoublyLinkedList.Node[] memory _borrowed = moneyMarketDs.subAccountDebtShares[_subAccount].getAll();

    uint256 _borrowedLength = _borrowed.length;

    address _borrowedToken;
    LibConstant.TokenConfig memory _tokenConfig;

    // sum up total used borrowing power from each borrowed token
    for (uint256 _i; _i < _borrowedLength; ) {
      _borrowedToken = _borrowed[_i].token;
      _tokenConfig = moneyMarketDs.tokenConfigs[_borrowedToken];

      if (_tokenConfig.tier == LibConstant.AssetTier.ISOLATE) {
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

  /// @dev Calculate total used borrowing power of a non collat borrower
  /// @param _account The non collat borrower address
  /// @param moneyMarketDs The storage of money market
  /// @return _totalUsedBorrowingPower The total used borrowing power of a non collat borrower
  function getTotalNonCollatUsedBorrowingPower(address _account, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _totalUsedBorrowingPower)
  {
    // get all borrowed positions of a non collat borrower
    LibDoublyLinkedList.Node[] memory _borrowed = moneyMarketDs.nonCollatAccountDebtValues[_account].getAll();

    uint256 _borrowedLength = _borrowed.length;

    LibConstant.TokenConfig memory _tokenConfig;
    address _borrowedToken;

    // sum up total used borrowing power from each borrowed token
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

  /// @dev Calculate used borrowing power of a token
  /// @param _subAccount The sub account address
  /// @param moneyMarketDs The storage of money market
  /// @return _totalBorrowedUSDValue The total borrowed USD value of a sub account
  function getTotalBorrowedUSDValue(address _subAccount, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _totalBorrowedUSDValue)
  {
    // get all borrowed positions of a sub account
    LibDoublyLinkedList.Node[] memory _borrowed = moneyMarketDs.subAccountDebtShares[_subAccount].getAll();

    uint256 _borrowedLength = _borrowed.length;

    address _borrowedToken;
    uint256 _borrowedAmount;

    // sum up total borrowed USD value from each borrowed token
    for (uint256 _i; _i < _borrowedLength; ) {
      _borrowedToken = _borrowed[_i].token;

      _borrowedAmount = LibShareUtil.shareToValue(
        _borrowed[_i].amount,
        moneyMarketDs.overCollatDebtValues[_borrowedToken],
        moneyMarketDs.overCollatDebtShares[_borrowedToken]
      );

      // calulation:
      // _totalBorrowedUSDValue += _borrowedAmount * tokenPrice
      //
      // example:
      //  - _borrowedAmount       = 100
      //  - tokenPrice            = 1.5
      //
      //  _totalBorrowingPower   += 100 * 1.5
      //                         += 150
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

  /// @dev Calculate used borrowing power of a token
  /// @param _borrowedAmount The borrowed amount
  /// @param _tokenPrice The token price
  /// @param _borrowingFactor The borrowing factor
  /// @param _to18ConversionFactor The conversion factor to 18 decimals
  function usedBorrowingPower(
    uint256 _borrowedAmount,
    uint256 _tokenPrice,
    uint256 _borrowingFactor,
    uint256 _to18ConversionFactor
  ) internal pure returns (uint256 _usedBorrowingPower) {
    // calulation:
    // usedBorrowingPower = borrowedAmountE18 * tokenPrice * (LibConstant.MAX_BPS / borrowingFactor)
    //
    // example:
    //  - borrowedAmountE18   = 100 (omit 1e18)
    //  - tokenPrice          = 1.5
    //  - LibConstant.MAX_BPS             = 10000
    //  - borrowingFactor     = 9000
    //
    //  usedBorrowingPower    = 100 * 1.5 * (10000 / 9000)
    //                        = 100 * 1.5 * 1.11111
    //                        = 166.67
    _usedBorrowingPower = LibFullMath.mulDiv(
      _borrowedAmount * _to18ConversionFactor,
      _tokenPrice,
      1e14 * _borrowingFactor // gas savings: 1e14 = 1e18 / LibConstant.MAX_BPS
    );
  }

  /// @dev Calculate global pending interest of a token
  /// @param _token The token address
  /// @param moneyMarketDs The storage of money market
  /// @return _globalPendingInterest The global pending interest of a token
  function getGlobalPendingInterest(address _token, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _globalPendingInterest)
  {
    uint256 _lastAccrualTimestamp = moneyMarketDs.debtLastAccruedAt[_token];

    // skip if interest has already been accrued within this block
    if (block.timestamp > _lastAccrualTimestamp) {
      // get a period of time since last accrual in seconds
      uint256 _secondsSinceLastAccrual;
      // safe to use unchecked
      //    because at this statement, block.timestamp is always greater than _lastAccrualTimestamp
      unchecked {
        _secondsSinceLastAccrual = block.timestamp - _lastAccrualTimestamp;
      }
      // get all non collat borrowers
      LibDoublyLinkedList.Node[] memory _borrowedAccounts = moneyMarketDs.nonCollatTokenDebtValues[_token].getAll();
      uint256 _accountLength = _borrowedAccounts.length;
      uint256 _nonCollatInterestPerSec;

      // sum up total non collat interest per second from each non collat borrower
      // calulation:
      // _nonCollatInterestPerSec += (nonCollatInterestRate * borrowedAmount)
      //
      // example:
      //  - nonCollatInterestRate   = 0.1
      //  - borrowedAmount          = 100
      //
      //  _nonCollatInterestPerSec += 0.1 * 100
      //                           += 10
      for (uint256 _i; _i < _accountLength; ) {
        _nonCollatInterestPerSec += (getNonCollatInterestRate(_borrowedAccounts[_i].token, _token, moneyMarketDs) *
          _borrowedAccounts[_i].amount);

        unchecked {
          ++_i;
        }
      }

      // calulations:
      // _globalPendingInterest = (nonCollatInterestAmountPerSec + overCollatInterestAmountPerSec) * _secondsSinceLastAccrual
      // overCollatInterestAmountPerSec = overCollatInterestRate * overCollatDebtValue
      //
      // example:
      //  - nonCollatInterestAmountPerSec   = 20
      //  - overCollatInterestAmountPerSec  = 0.1 * 50
      //  - _secondsSinceLastAccrual        = 3200
      //
      //  _globalPendingInterest            = (20 + (0.1 * 50)) * 3200
      //                                    = 25 * 3200
      //                                    = 80000
      _globalPendingInterest =
        ((_nonCollatInterestPerSec +
          (getOverCollatInterestRate(_token, moneyMarketDs) * moneyMarketDs.overCollatDebtValues[_token])) *
          _secondsSinceLastAccrual) /
        1e18;
    }
  }

  /// @dev Get over collat interest rate of a token
  /// @param _token The token address
  /// @param moneyMarketDs The storage of money market
  /// @return _interestRate The interest rate of a token
  function getOverCollatInterestRate(address _token, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _interestRate)
  {
    // get interest model of a token
    IInterestRateModel _interestModel = moneyMarketDs.interestModels[_token];
    // return 0 if interest model does not exist
    // otherwise, return interest rate from interest model
    if (address(_interestModel) == address(0)) {
      return 0;
    }
    _interestRate = _interestModel.getInterestRate(moneyMarketDs.globalDebts[_token], moneyMarketDs.reserves[_token]);
  }

  /// @dev Get non collat interest rate
  /// @param _account The account address
  /// @param _token The token address
  /// @param moneyMarketDs The storage of money market
  /// @return _interestRate The non collat interest rate
  function getNonCollatInterestRate(
    address _account,
    address _token,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _interestRate) {
    // get interest model of a token in a non collat account
    IInterestRateModel _interestModel = moneyMarketDs.nonCollatInterestModels[_account][_token];
    // return 0 if interest model does not exist
    // otherwise, return interest rate from interest model
    if (address(_interestModel) == address(0)) {
      return 0;
    }
    _interestRate = _interestModel.getInterestRate(moneyMarketDs.globalDebts[_token], moneyMarketDs.reserves[_token]);
  }

  /// @dev Accrue over collat interest of a token
  /// @param _token The token address
  /// @param _timePast The time past since last accrual
  /// @param moneyMarketDs The storage of money market
  /// @return _overCollatInterest The over collat interest of a token
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

  /// @dev Accrue over collat and non collat interest of a token
  /// @param _token The token address
  /// @param moneyMarketDs The storage of money market
  function accrueInterest(address _token, MoneyMarketDiamondStorage storage moneyMarketDs) internal {
    uint256 _lastAccrualTimestamp = moneyMarketDs.debtLastAccruedAt[_token];
    // skip if interest has already been accrued within this block
    if (block.timestamp > _lastAccrualTimestamp) {
      // get a period of time since last accrual in seconds
      uint256 _secondsSinceLastAccrual;
      // safe to use unchecked
      //    because at this statement, block.timestamp is always greater than _lastAccrualTimestamp
      unchecked {
        _secondsSinceLastAccrual = block.timestamp - _lastAccrualTimestamp;
      }
      // accrue interest
      uint256 _overCollatInterest = accrueOverCollatInterest(_token, _secondsSinceLastAccrual, moneyMarketDs);
      uint256 _nonCollatInterest = accrueNonCollatInterest(_token, _secondsSinceLastAccrual, moneyMarketDs);

      // update global debt
      uint256 _totalInterest = _overCollatInterest + _nonCollatInterest;
      moneyMarketDs.globalDebts[_token] += _totalInterest;

      // update timestamp
      moneyMarketDs.debtLastAccruedAt[_token] = block.timestamp;

      // book protocol's revenue
      // calculation:
      // _protocolFee = (_totalInterest * lendingFeeBps) / LibConstant.MAX_BPS
      //
      // example:
      //  - _totalInterest = 1
      //  - lendingFeeBps  = 1900
      //  - LibConstant.MAX_BPS        = 10000
      //
      //  _protocolFee     = (1 * 1900) / 10000
      //                   = 0.19
      uint256 _protocolFee = (_totalInterest * moneyMarketDs.lendingFeeBps) / LibConstant.MAX_BPS;
      moneyMarketDs.protocolReserves[_token] += _protocolFee;

      emit LogAccrueInterest(_token, _totalInterest, _protocolFee);
    }
  }

  /// @dev Accrue non collat interest of a token
  /// @param _token The token address
  /// @param _timePast The time past since last accrual
  /// @param moneyMarketDs The storage of money market
  /// @return _totalNonCollatInterest The total non collat interest of a token
  function accrueNonCollatInterest(
    address _token,
    uint256 _timePast,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal returns (uint256 _totalNonCollatInterest) {
    // get all non collat borrowers
    LibDoublyLinkedList.Node[] memory _borrowedAccounts = moneyMarketDs.nonCollatTokenDebtValues[_token].getAll();
    uint256 _accountLength = _borrowedAccounts.length;
    address _account;
    uint256 _currentAccountDebt;
    uint256 _accountInterest;
    uint256 _newNonCollatDebtValue;

    // sum up all non collat interest of a token
    for (uint256 _i; _i < _accountLength; ) {
      _account = _borrowedAccounts[_i].token;
      _currentAccountDebt = _borrowedAccounts[_i].amount;

      // calculate interest
      // calculation:
      // _accountInterest = nonCollatInterestRate * _timePast * _currentAccountDebt
      //
      // example:
      //  - nonCollatInterestRate = 0.1
      //  - _timePast             = 3200
      //  - _currentAccountDebt   = 100
      //
      //  _accountInterest        = 0.1 * 3200 * 100
      //                          = 32000
      _accountInterest =
        (getNonCollatInterestRate(_account, _token, moneyMarketDs) * _timePast * _currentAccountDebt) /
        1e18;

      // update non collat debt states
      _newNonCollatDebtValue = _currentAccountDebt + _accountInterest;
      // 1. account debt
      moneyMarketDs.nonCollatAccountDebtValues[_account].addOrUpdate(_token, _newNonCollatDebtValue);
      // 2. token debt
      moneyMarketDs.nonCollatTokenDebtValues[_token].addOrUpdate(_account, _newNonCollatDebtValue);

      // accumulate total non collat interest
      _totalNonCollatInterest += _accountInterest;
      unchecked {
        ++_i;
      }
    }
  }

  /// @dev Accrue interest of all borrowed positions of a sub account
  /// @param _subAccount The sub account address
  /// @param moneyMarketDs The storage of money market
  function accrueBorrowedPositionsOf(address _subAccount, MoneyMarketDiamondStorage storage moneyMarketDs) internal {
    // get all borrowed positions of a sub account
    LibDoublyLinkedList.Node[] memory _borrowed = moneyMarketDs.subAccountDebtShares[_subAccount].getAll();

    uint256 _borrowedLength = _borrowed.length;

    // accrue interest of all borrowed positions
    for (uint256 _i; _i < _borrowedLength; ) {
      accrueInterest(_borrowed[_i].token, moneyMarketDs);
      unchecked {
        ++_i;
      }
    }
  }

  /// @dev Accrue interest of all non collat borrowed positions of a non collat borrower
  /// @param _account The non collat borrower address
  /// @param moneyMarketDs The storage of money market
  function accrueNonCollatBorrowedPositionsOf(address _account, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
  {
    // get all borrowed positions of a non collat borrower
    LibDoublyLinkedList.Node[] memory _borrowed = moneyMarketDs.nonCollatAccountDebtValues[_account].getAll();

    uint256 _borrowedLength = _borrowed.length;

    // accrue interest of all borrowed positions
    for (uint256 _i; _i < _borrowedLength; ) {
      accrueInterest(_borrowed[_i].token, moneyMarketDs);
      unchecked {
        ++_i;
      }
    }
  }

  /// @dev Get total amount of a token in money market
  /// @param _token The token address
  /// @param moneyMarketDs The storage of money market
  /// @return The total amount of a token in money market
  function getTotalToken(address _token, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256)
  {
    // calculation:
    // totalToken   = amount of token remains in money market + debt - protocol reserve
    // debt         = over collat debt + non collat debt
    //
    // example:
    //  - amount of token remains in money markey = 100
    //  - over collat debt                        = 200
    //  - non collat debt                         = 300
    //  - protocol reserve                        = 50
    //
    //  totalToken                                = 100 + (200 + 300) - 50
    //                                            = 100 + (500) - 50
    //                                            = 550
    return
      (moneyMarketDs.reserves[_token] + moneyMarketDs.globalDebts[_token]) - (moneyMarketDs.protocolReserves[_token]);
  }

  /// @dev Get total amount of a token in money market with pending interest
  /// @param _token The token address
  /// @param moneyMarketDs The storage of money market
  /// @return The total amount of a token in money market with pending interest
  function getTotalTokenWithPendingInterest(address _token, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256)
  {
    // calculation:
    // totalTokenWithPendingInterest = totalToken + ((pendingInterest * (LibConstant.MAX_BPS - lendingFeeBps)) / LibConstant.MAX_BPS)
    //
    // example:
    //  - totalToken                  = 550
    //  - pendingInterest             = 100
    //  - lendingFeeBps               = 1900
    //  - LibConstant.MAX_BPS                     = 10000
    //
    //  totalTokenWithPendingInterest = 550 + ((100 * (10000 - 1900)) / 10000)
    //                                = 550 + ((100 * 8100) / 10000)
    //                                = 550 + (810000 / 10000)
    //                                = 550 + 81
    //                                = 631
    return
      getTotalToken(_token, moneyMarketDs) +
      ((getGlobalPendingInterest(_token, moneyMarketDs) * (LibConstant.MAX_BPS - moneyMarketDs.lendingFeeBps)) /
        LibConstant.MAX_BPS);
  }

  /// @dev Get price of a token in USD
  /// @param _token The token address
  /// @param moneyMarketDs The storage of money market
  /// @return _price The price of a token in USD
  function getPriceUSD(address _token, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _price)
  {
    address _underlyingToken = moneyMarketDs.ibTokenToTokens[_token];
    // If the token is ibToken, do an additional shareToValue before pricing
    // otherwise, just get the price from oracle
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

  /// @dev Get to18ConversionFactor of a token
  /// @param _token The token address
  /// @return The to18ConversionFactor of a token
  function to18ConversionFactor(address _token) internal view returns (uint64) {
    // get decimals of a token
    uint256 _decimals = IERC20(_token).decimals();
    // revert if decimals > 18
    if (_decimals > 18) {
      revert LibMoneyMarket01_UnsupportedDecimals();
    }
    // in case the decimal is in 18 digits, the factor is 1
    // and can skip the below calculation
    if (_decimals == 18) {
      return 1;
    }
    // calculate conversion factor
    // calculation:
    // conversionFactor = 10^(18 - decimals)
    //
    // example:
    //  - decimals        = 6
    //
    //  conversionFactor  = 10^(18 - 6)
    //                    = 10^(12)
    //                    = 1e12
    uint256 _conversionFactor = 10**(18 - _decimals);
    return uint64(_conversionFactor);
  }

  /// @dev Add collat to sub account
  /// @param _account The account address
  /// @param _subAccount The sub account address
  /// @param _token The token address
  /// @param _addAmount The amount to add
  /// @param moneyMarketDs The storage of money market
  function addCollatToSubAccount(
    address _account,
    address _subAccount,
    address _token,
    uint256 _addAmount,
    bool _skipMiniFL,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    // validation
    //  1. revert if token is not collateral
    if (moneyMarketDs.tokenConfigs[_token].tier != LibConstant.AssetTier.COLLATERAL) {
      revert LibMoneyMarket01_InvalidAssetTier();
    }
    //  2. revert if _addAmount + currentCollatAmount exceed max collateral amount of a token
    if (_addAmount + moneyMarketDs.collats[_token] > moneyMarketDs.tokenConfigs[_token].maxCollateral) {
      revert LibMoneyMarket01_ExceedCollateralLimit();
    }

    // init list
    LibDoublyLinkedList.List storage subAccountCollateralList = moneyMarketDs.subAccountCollats[_subAccount];
    subAccountCollateralList.initIfNotExist();

    // TODO: optimize this
    uint256 _currentCollatAmount = subAccountCollateralList.getAmount(_token);
    // update states
    //  1. update sub account collateral amount
    subAccountCollateralList.addOrUpdate(_token, _currentCollatAmount + _addAmount);
    // revert if number of collateral tokens exceed limit per sub account
    if (subAccountCollateralList.length() > moneyMarketDs.maxNumOfCollatPerSubAccount) {
      revert LibMoneyMarket01_NumberOfTokenExceedLimit();
    }
    //  2. update total collateral amount of a token in money market
    moneyMarketDs.collats[_token] += _addAmount;

    // if called by transferCollateral, does not need to deposit to miniFL
    // as during removeCollateral in transfer, token wasn't withdrawn from miniFL
    if (!_skipMiniFL) {
      // stake token to miniFL, when user add collateral by ibToken
      uint256 _poolId = moneyMarketDs.miniFLPoolIds[_token];

      // If the collateral token has no miniFL's poolID associated with it
      // skip the deposit to miniFL process
      // This generally applies to non-ibToken collateral
      if (_poolId != 0) {
        IMiniFL _miniFL = moneyMarketDs.miniFL;
        IERC20(_token).safeApprove(address(_miniFL), _addAmount);
        _miniFL.deposit(_account, _poolId, _addAmount);
      }
    }

    emit LogAddCollateral(_account, _subAccount, _token, msg.sender, _addAmount);
  }

  /// @dev Remove collat from sub account
  /// @param _account The account address
  /// @param _subAccount The sub account address
  /// @param _token The token address
  /// @param _removeAmount The amount to remove
  /// @param moneyMarketDs The storage of money market
  function removeCollatFromSubAccount(
    address _account,
    address _subAccount,
    address _token,
    uint256 _removeAmount,
    bool _skipMiniFl,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    // get current collateral amount of a token
    LibDoublyLinkedList.List storage _subAccountCollatList = moneyMarketDs.subAccountCollats[_subAccount];
    uint256 _currentCollatAmount = _subAccountCollatList.getAmount(_token);

    // revert if insufficient collateral amount to remove
    if (_removeAmount > _currentCollatAmount) {
      revert LibMoneyMarket01_TooManyCollateralRemoved();
    }
    // update states
    //  1. update sub account collateral amount
    _subAccountCollatList.updateOrRemove(_token, _currentCollatAmount - _removeAmount);
    //  2. update total collateral amount of a token in money market
    moneyMarketDs.collats[_token] -= _removeAmount;

    // if called by transferCollateral, does not need to withdraw from miniFL
    if (!_skipMiniFl) {
      // In the subsequent call, money market should get hold of physical token to proceed
      // Thus, we need to withdraw the physical token from miniFL first
      uint256 _poolId = moneyMarketDs.miniFLPoolIds[_token];

      // If the collateral token has no miniFL's poolID associated with it
      // skip the withdrawal from miniFL process
      // This generally applies to non-ibToken collateral
      if (_poolId != 0) {
        moneyMarketDs.miniFL.withdraw(_account, _poolId, _removeAmount);
      }
    }

    emit LogRemoveCollateral(_account, _subAccount, _token, _removeAmount);
  }

  /// @dev Validate if sub account is healthy
  /// @param _subAccount The sub account address
  /// @param moneyMarketDs The storage of money market
  function validateSubaccountIsHealthy(address _subAccount, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
  {
    uint256 _totalBorrowingPower = getTotalBorrowingPower(_subAccount, moneyMarketDs);
    (uint256 _totalUsedBorrowingPower, ) = getTotalUsedBorrowingPower(_subAccount, moneyMarketDs);
    // revert if total borrowing power is less than total used borrowing power
    // in case of price change, this can happen
    if (_totalBorrowingPower < _totalUsedBorrowingPower) {
      revert LibMoneyMarket01_BorrowingPowerTooLow();
    }
  }

  /// @dev Remove over collat debt from sub account
  /// @param _account The account address
  /// @param _subAccount The sub account address
  /// @param _repayToken The token address
  /// @param _debtShareToRemove The debt share to remove
  /// @param _debtValueToRemove The debt value to remove
  /// @param moneyMarketDs The storage of money market
  function removeOverCollatDebtFromSubAccount(
    address _account,
    address _subAccount,
    address _repayToken,
    uint256 _debtShareToRemove,
    uint256 _debtValueToRemove,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    LibDoublyLinkedList.List storage userDebtShare = moneyMarketDs.subAccountDebtShares[_subAccount];
    // get current debt share of a token
    uint256 _currentDebtShare = userDebtShare.getAmount(_repayToken);

    // update states
    //  1. update sub account debt share
    userDebtShare.updateOrRemove(_repayToken, _currentDebtShare - _debtShareToRemove);
    //  2. update total over collat debt share of a token in money market
    moneyMarketDs.overCollatDebtShares[_repayToken] -= _debtShareToRemove;
    //  3. update total over collat debt value of a token in money market
    moneyMarketDs.overCollatDebtValues[_repayToken] -= _debtValueToRemove;
    //  4. update total debt value of a token in money market
    moneyMarketDs.globalDebts[_repayToken] -= _debtValueToRemove;

    // withdraw debt token from miniFL
    IMiniFL _miniFL = moneyMarketDs.miniFL;
    address _debtToken = moneyMarketDs.tokenToDebtTokens[_repayToken];
    _miniFL.withdraw(_account, moneyMarketDs.miniFLPoolIds[_debtToken], _debtShareToRemove);

    // burn debt token
    IDebtToken(_debtToken).burn(address(this), _debtShareToRemove);

    emit LogRemoveDebt(
      _account,
      _subAccount,
      _repayToken,
      _debtShareToRemove,
      _debtValueToRemove,
      userDebtShare.length()
    );
  }

  /// @dev Transfer collat from one sub account to another
  /// @param _toSubAccount The sub account address to transfer to
  /// @param _token The token address
  /// @param _transferAmount The amount to transfer
  /// @param moneyMarketDs The storage of money market
  function transferCollat(
    address _toSubAccount,
    address _token,
    uint256 _transferAmount,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    // init list
    LibDoublyLinkedList.List storage toSubAccountCollateralList = moneyMarketDs.subAccountCollats[_toSubAccount];
    toSubAccountCollateralList.initIfNotExist();

    uint256 _currentCollatAmount = toSubAccountCollateralList.getAmount(_token);
    // update toSubAccount collateral amount
    toSubAccountCollateralList.addOrUpdate(_token, _currentCollatAmount + _transferAmount);
    // revert if number of collateral tokens exceed limit per sub account
    if (toSubAccountCollateralList.length() > moneyMarketDs.maxNumOfCollatPerSubAccount) {
      revert LibMoneyMarket01_NumberOfTokenExceedLimit();
    }
  }

  /// @dev Get over collat debt share and amount
  /// @param _subAccount The sub account address
  /// @param _token The token address
  /// @param moneyMarketDs The storage of money market
  /// @return _debtShare The debt share
  /// @return _debtAmount The debt amount
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

  /// @dev Get non collat debt amount
  /// @param _account The non collat borrower address
  /// @param _token The token address
  /// @param moneyMarketDs The storage of money market
  /// @return _debtAmount The debt amount
  function getNonCollatDebt(
    address _account,
    address _token,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _debtAmount) {
    _debtAmount = moneyMarketDs.nonCollatAccountDebtValues[_account].getAmount(_token);
  }

  /// @dev Do over collat borrow
  /// @param _account The account address
  /// @param _subAccount The sub account address
  /// @param _token The token address
  /// @param _amount The amount to borrow
  /// @param moneyMarketDs The storage of money market
  /// @return _shareToAdd The share value to add
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

    // get share value to update states
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
    // revert if number of debt tokens exceed limit per sub account
    uint256 _userDebtShareLen = userDebtShare.length();
    if (_userDebtShareLen > moneyMarketDs.maxNumOfDebtPerSubAccount) {
      revert LibMoneyMarket01_NumberOfTokenExceedLimit();
    }

    // mint debt token to money market and stake to miniFL
    address _debtToken = moneyMarketDs.tokenToDebtTokens[_token];

    // pool for debt token always exist
    // since pool is created during AdminFacet.openMarket()
    IDebtToken(_debtToken).mint(address(this), _shareToAdd);
    IERC20(_debtToken).safeApprove(address(_miniFL), _shareToAdd);
    _miniFL.deposit(_account, moneyMarketDs.miniFLPoolIds[_debtToken], _shareToAdd);

    emit LogOverCollatBorrow(_account, _subAccount, _token, _amount, _shareToAdd, _userDebtShareLen);
  }

  /// @dev Do non collat borrow
  /// @param _account The non collat borrower address
  /// @param _token The token address
  /// @param _amount The amount to borrow
  /// @param moneyMarketDs The storage of money market
  function nonCollatBorrow(
    address _account,
    address _token,
    uint256 _amount,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    // init lists
    //  1. debtValue
    LibDoublyLinkedList.List storage debtValue = moneyMarketDs.nonCollatAccountDebtValues[_account];
    debtValue.initIfNotExist();

    //  2. tokenDebts
    LibDoublyLinkedList.List storage tokenDebts = moneyMarketDs.nonCollatTokenDebtValues[_token];
    tokenDebts.initIfNotExist();

    // update account debt
    uint256 _newAccountDebt = debtValue.getAmount(_token) + _amount;
    uint256 _newTokenDebt = tokenDebts.getAmount(msg.sender) + _amount;

    debtValue.addOrUpdate(_token, _newAccountDebt);

    // revert if number of debt value exceed limit per non collat account
    if (debtValue.length() > moneyMarketDs.maxNumOfDebtPerNonCollatAccount) {
      revert LibMoneyMarket01_NumberOfTokenExceedLimit();
    }

    tokenDebts.addOrUpdate(msg.sender, _newTokenDebt);

    // update global debt
    moneyMarketDs.globalDebts[_token] += _amount;
  }

  /// @dev SafeTransferFrom that revert when not receiving full amount (have fee on transfer)
  /// @param _token The token address
  /// @param _from The address to pull token from
  /// @param _amount The amount to pull
  function pullExactTokens(
    address _token,
    address _from,
    uint256 _amount
  ) internal {
    // get the token balance of money market before transfer
    uint256 _balanceBefore = IERC20(_token).balanceOf(address(this));
    // transfer token from _from to money market
    IERC20(_token).safeTransferFrom(_from, address(this), _amount);
    // check if the token balance of money market is increased by _amount
    // if fee on transer tokens is not supported this will revert
    if (IERC20(_token).balanceOf(address(this)) - _balanceBefore != _amount) {
      revert LibMoneyMarket01_FeeOnTransferTokensNotSupported();
    }
  }

  /// @dev SafeTransferFrom that return actual amount received
  /// @param _token The token address
  /// @param _from The address to pull token from
  /// @param _amount The amount to pull
  /// @return _actualAmountReceived The actual amount received
  function unsafePullTokens(
    address _token,
    address _from,
    uint256 _amount
  ) internal returns (uint256 _actualAmountReceived) {
    // get the token balance of money market before transfer
    uint256 _balanceBefore = IERC20(_token).balanceOf(address(this));
    // transfer token from _from to money market
    IERC20(_token).safeTransferFrom(_from, address(this), _amount);
    // return actual amount received = balance after transfer - balance before transfer
    _actualAmountReceived = IERC20(_token).balanceOf(address(this)) - _balanceBefore;
  }

  /// @dev Check if the money market is live, revert when not live
  /// @param moneyMarketDs The storage of money market
  function onlyLive(MoneyMarketDiamondStorage storage moneyMarketDs) internal view {
    if (moneyMarketDs.emergencyPaused) {
      revert LibMoneyMarket01_EmergencyPaused();
    }
  }

  /// @dev Check if caller is account manager, revert when not account manager
  /// @param moneyMarketDs The storage of money market
  function onlyAccountManager(MoneyMarketDiamondStorage storage moneyMarketDs) internal view {
    if (!moneyMarketDs.accountManagersOk[msg.sender]) {
      revert LibMoneyMarket01_UnAuthorized();
    }
  }

  /// @dev Write off the subaccount's debt that has no collateral backed
  /// WARNING: Only called this when all interests have been accrued
  /// @param _subAccount The subAccount to be written off
  /// @param moneyMarketDs The storage of money market
  function writeOffBadDebt(
    address _account,
    address _subAccount,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    // skip this if there're still collaterals under the subAccount
    if (moneyMarketDs.subAccountCollats[_subAccount].size != 0) {
      return;
    }

    LibDoublyLinkedList.Node[] memory _borrowed = moneyMarketDs.subAccountDebtShares[_subAccount].getAll();

    address _token;
    uint256 _shareToRemove;
    uint256 _amountToRemove;
    uint256 _length = _borrowed.length;

    // loop over all outstanding debt
    for (uint256 _i; _i < _length; ) {
      _token = _borrowed[_i].token;
      _shareToRemove = _borrowed[_i].amount;

      // Price in the actual amount to be written off
      _amountToRemove = LibShareUtil.shareToValue(
        _shareToRemove,
        moneyMarketDs.overCollatDebtValues[_token],
        moneyMarketDs.overCollatDebtShares[_token]
      );

      // Reset debts of the token under subAccount
      removeOverCollatDebtFromSubAccount(_account, _subAccount, _token, _shareToRemove, _amountToRemove, moneyMarketDs);

      emit LogWriteOffSubAccountDebt(_subAccount, _token, _shareToRemove, _amountToRemove);

      unchecked {
        ++_i;
      }
    }
  }
}
