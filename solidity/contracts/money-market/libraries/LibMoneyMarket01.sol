// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// libs
import { LibDoublyLinkedList } from "./LibDoublyLinkedList.sol";
import { LibFullMath } from "./LibFullMath.sol";
import { LibShareUtil } from "./LibShareUtil.sol";
import { LibReward } from "./LibReward.sol";

// interfaces
import { IERC20 } from "../interfaces/IERC20.sol";
import { IIbToken } from "../interfaces/IIbToken.sol";
import { IPriceOracle } from "../interfaces/IPriceOracle.sol";
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";

library LibMoneyMarket01 {
  using LibDoublyLinkedList for LibDoublyLinkedList.List;
  using SafeERC20 for ERC20;
  using SafeCast for uint256;

  // keccak256("moneymarket.diamond.storage");
  bytes32 internal constant MONEY_MARKET_STORAGE_POSITION =
    0x2758c6926500ec9dc8ab8cea4053d172d4f50d9b78a6c2ee56aa5dd18d2c800b;

  uint256 internal constant MAX_BPS = 10000;
  uint256 internal constant ACC_REWARD_PRECISION = 1e12;

  error LibMoneyMarket01_BadSubAccountId();
  error LibMoneyMarket01_PriceStale(address);
  error LibMoneyMarket01_InvalidToken(address _token);
  error LibMoneyMarket01_NoTinyShares();
  error LibMoneyMarket01_UnsupportedDecimals();
  error LibMoneyMarket01_InvalidAssetTier();
  error LibMoneyMarket01_ExceedCollateralLimit();
  error LibMoneyMarket01_TooManyCollateralRemoved();
  error LibMoneyMarket01_BorrowingPowerTooLow();

  event LogWithdraw(address indexed _user, address _token, address _ibToken, uint256 _amountIn, uint256 _amountOut);

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
    uint256 maxCollateral;
    uint256 maxBorrow;
    uint256 maxToleranceExpiredSecond;
    uint8 to18ConversionFactor;
  }

  struct RewardConfig {
    address rewardToken;
    uint256 rewardPerSecond;
  }

  struct PoolInfo {
    uint256 accRewardPerShare;
    uint128 lastRewardTime;
    uint128 allocPoint;
  }

  // Storage
  struct MoneyMarketDiamondStorage {
    address nativeToken;
    address nativeRelayer;
    mapping(address => address) tokenToIbTokens;
    mapping(address => address) ibTokenToTokens;
    mapping(address => uint256) debtValues;
    mapping(address => uint256) debtShares;
    mapping(address => uint256) globalDebts;
    mapping(address => uint256) collats;
    mapping(address => LibDoublyLinkedList.List) subAccountCollats;
    mapping(address => LibDoublyLinkedList.List) subAccountDebtShares;
    // account -> list token debt
    mapping(address => LibDoublyLinkedList.List) nonCollatAccountDebtValues;
    // token -> debt of each account
    mapping(address => LibDoublyLinkedList.List) nonCollatTokenDebtValues;
    // account -> limit
    mapping(address => uint256) nonCollatBorrowLimitUSDValues;
    mapping(address => bool) nonCollatBorrowerOk;
    mapping(address => TokenConfig) tokenConfigs;
    IPriceOracle oracle;
    mapping(address => uint256) debtLastAccureTime;
    mapping(address => IInterestRateModel) interestModels;
    mapping(bytes32 => IInterestRateModel) nonCollatInterestModels;
    mapping(address => bool) repurchasersOk;
    mapping(address => bool) liquidationStratOk;
    mapping(address => bool) liquidationCallersOk;
    // reward stuff
    address rewardDistributor;
    mapping(address => mapping(address => uint256)) accountCollats; // amount in user info
    // token => pool info
    mapping(address => PoolInfo) poolInfos;
    // account => pool key (token) => amount
    mapping(address => mapping(address => int256)) accountRewardDebts;
    RewardConfig rewardConfig;
    uint256 totalAllocPoint;
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

    uint256 _collatsLength = _collats.length;

    for (uint256 _i = 0; _i < _collatsLength; ) {
      address _collatToken = _collats[_i].token;
      uint256 _collatAmount = _collats[_i].amount;
      uint256 _actualAmount = _collatAmount;

      // will return address(0) if _collatToken is not ibToken
      address _actualToken = moneyMarketDs.ibTokenToTokens[_collatToken];
      if (_actualToken == address(0)) {
        _actualToken = _collatToken;
      } else {
        uint256 _totalSupply = IIbToken(_collatToken).totalSupply();
        uint256 _totalToken = getTotalToken(_actualToken, moneyMarketDs);

        _actualAmount = LibShareUtil.shareToValue(_collatAmount, _totalToken, _totalSupply);
      }

      TokenConfig memory _tokenConfig = moneyMarketDs.tokenConfigs[_actualToken];

      (uint256 _tokenPrice, ) = getPriceUSD(_actualToken, moneyMarketDs);

      // _totalBorrowingPowerUSDValue += amount * tokenPrice * collateralFactor
      _totalBorrowingPowerUSDValue += LibFullMath.mulDiv(
        _actualAmount * _tokenConfig.to18ConversionFactor * _tokenConfig.collateralFactor,
        _tokenPrice,
        1e22
      );

      unchecked {
        _i++;
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

    for (uint256 _i = 0; _i < _length; ) {
      _totalNonCollatDebt += _nonCollatDebts[_i].amount;

      unchecked {
        _i++;
      }
    }
  }

  function getTotalUsedBorrowedPower(address _subAccount, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _totalUsedBorrowedPower, bool _hasIsolateAsset)
  {
    LibDoublyLinkedList.Node[] memory _borrowed = moneyMarketDs.subAccountDebtShares[_subAccount].getAll();

    uint256 _borrowedLength = _borrowed.length;

    for (uint256 _i = 0; _i < _borrowedLength; ) {
      TokenConfig memory _tokenConfig = moneyMarketDs.tokenConfigs[_borrowed[_i].token];

      if (_tokenConfig.tier == LibMoneyMarket01.AssetTier.ISOLATE) {
        _hasIsolateAsset = true;
      }

      (uint256 _tokenPrice, ) = getPriceUSD(_borrowed[_i].token, moneyMarketDs);

      uint256 _borrowedAmount = LibShareUtil.shareToValue(
        _borrowed[_i].amount,
        moneyMarketDs.debtValues[_borrowed[_i].token],
        moneyMarketDs.debtShares[_borrowed[_i].token]
      );

      _totalUsedBorrowedPower += usedBorrowedPower(_borrowedAmount, _tokenPrice, _tokenConfig.borrowingFactor);

      unchecked {
        _i++;
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

    for (uint256 _i = 0; _i < _borrowedLength; ) {
      (uint256 _tokenPrice, ) = getPriceUSD(_borrowed[_i].token, moneyMarketDs);
      uint256 _borrowedAmount = LibShareUtil.shareToValue(
        _borrowed[_i].amount,
        moneyMarketDs.debtValues[_borrowed[_i].token],
        moneyMarketDs.debtShares[_borrowed[_i].token]
      );

      TokenConfig memory _tokenConfig = moneyMarketDs.tokenConfigs[_borrowed[_i].token];
      // _totalBorrowedUSDValue += _borrowedAmount * tokenPrice
      _totalBorrowedUSDValue += LibFullMath.mulDiv(
        _borrowedAmount * _tokenConfig.to18ConversionFactor,
        _tokenPrice,
        1e18
      );

      unchecked {
        _i++;
      }
    }
  }

  // _usedBorrowedPower += _borrowedAmount * tokenPrice * (10000/ borrowingFactor)
  function usedBorrowedPower(
    uint256 _borrowedAmount,
    uint256 _tokenPrice,
    uint256 _borrowingFactor
  ) internal pure returns (uint256 _usedBorrowedPower) {
    _usedBorrowedPower = LibFullMath.mulDiv(_borrowedAmount * MAX_BPS, _tokenPrice, 1e18 * uint256(_borrowingFactor));
  }

  function pendingInterest(address _token, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _pendingInterest)
  {
    uint256 _lastAccureTime = moneyMarketDs.debtLastAccureTime[_token];
    if (block.timestamp > _lastAccureTime) {
      uint256 _timePast = block.timestamp - _lastAccureTime;

      // over collat interest
      if (address(moneyMarketDs.interestModels[_token]) == address(0)) {
        return 0;
      }

      uint256 _interestRatePerSec = getOverCollatInterestRate(_token, moneyMarketDs);

      _pendingInterest = (_interestRatePerSec * _timePast * moneyMarketDs.debtValues[_token]) / 1e18;

      // non collat interest
      LibDoublyLinkedList.Node[] memory _borrowedAccounts = moneyMarketDs.nonCollatTokenDebtValues[_token].getAll();
      uint256 _accountLength = _borrowedAccounts.length;
      for (uint256 _i = 0; _i < _accountLength; ) {
        address _account = _borrowedAccounts[_i].token;

        uint256 _nonCollatInterestRate = getNonCollatInterestRate(_account, _token, moneyMarketDs);

        _pendingInterest += (_nonCollatInterestRate * _timePast * _borrowedAccounts[_i].amount) / 1e18;

        unchecked {
          _i++;
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

  function accureInterest(address _token, MoneyMarketDiamondStorage storage moneyMarketDs) internal {
    uint256 _lastAccureTime = moneyMarketDs.debtLastAccureTime[_token];
    if (block.timestamp > _lastAccureTime) {
      uint256 _timePast = block.timestamp - _lastAccureTime;
      //-----------------------------------------------------
      // over collat
      uint256 _overCollatInterest = (getOverCollatInterestRate(_token, moneyMarketDs) *
        _timePast *
        moneyMarketDs.debtValues[_token]) / 1e18;

      // non collat
      uint256 _totalNonCollatInterest = accrueNonCollatDebt(_token, _timePast, moneyMarketDs);

      // update global debt
      moneyMarketDs.globalDebts[_token] += (_overCollatInterest + _totalNonCollatInterest);
      // update overcollat debt
      moneyMarketDs.debtValues[_token] += _overCollatInterest;
      // update timestamp
      moneyMarketDs.debtLastAccureTime[_token] = block.timestamp;
    }
  }

  function accrueNonCollatDebt(
    address _token,
    uint256 _timePast,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal returns (uint256 _totalNonCollatInterest) {
    LibDoublyLinkedList.Node[] memory _borrowedAccounts = moneyMarketDs.nonCollatTokenDebtValues[_token].getAll();
    uint256 _accountLength = _borrowedAccounts.length;
    for (uint256 _i = 0; _i < _accountLength; ) {
      address _account = _borrowedAccounts[_i].token;
      uint256 _oldAccountDebt = _borrowedAccounts[_i].amount;

      uint256 _nonCollatInterestRate = getNonCollatInterestRate(_account, _token, moneyMarketDs);

      uint256 _accountInterest = (_nonCollatInterestRate * _timePast * _oldAccountDebt) / 1e18;

      // update non collat debt states
      // 1. account debt
      moneyMarketDs.nonCollatAccountDebtValues[_account].updateOrRemove(_token, _oldAccountDebt + _accountInterest);

      // 2. token debt
      moneyMarketDs.nonCollatTokenDebtValues[_token].updateOrRemove(_account, _oldAccountDebt + _accountInterest);

      _totalNonCollatInterest += _accountInterest;
      unchecked {
        _i++;
      }
    }
  }

  function accureAllSubAccountDebtToken(address _subAccount, MoneyMarketDiamondStorage storage moneyMarketDs) internal {
    LibDoublyLinkedList.Node[] memory _borrowed = moneyMarketDs.subAccountDebtShares[_subAccount].getAll();

    uint256 _borrowedLength = _borrowed.length;

    for (uint256 _i = 0; _i < _borrowedLength; ) {
      accureInterest(_borrowed[_i].token, moneyMarketDs);
      unchecked {
        _i++;
      }
    }
  }

  // totalToken is the amount of token remains in MM + borrowed amount - collateral from user
  // where borrowed amount consists of over-collat and non-collat borrowing
  function getTotalToken(address _token, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256)
  {
    return
      (IERC20(_token).balanceOf(address(this)) + moneyMarketDs.globalDebts[_token]) - moneyMarketDs.collats[_token];
  }

  function getFloatingBalance(address _token, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _floating)
  {
    _floating = IERC20(_token).balanceOf(address(this)) - moneyMarketDs.collats[_token];
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
    returns (uint256, uint256)
  {
    (uint256 _price, uint256 _lastUpdated) = moneyMarketDs.oracle.getPrice(
      _token,
      address(0x115dffFFfffffffffFFFffffFFffFfFfFFFFfFff)
    );
    if (_lastUpdated < block.timestamp - moneyMarketDs.tokenConfigs[_token].maxToleranceExpiredSecond)
      revert LibMoneyMarket01_PriceStale(_token);
    return (_price, _lastUpdated);
  }

  function getIbPriceUSD(
    address _ibToken,
    address _token,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256, uint256) {
    (uint256 _underlyingTokenPrice, uint256 _lastUpdated) = getPriceUSD(_token, moneyMarketDs);
    uint256 _totalSupply = IERC20(_ibToken).totalSupply();
    uint256 _one = 10**IERC20(_ibToken).decimals();

    uint256 _totalToken = getTotalToken(_token, moneyMarketDs);
    uint256 _ibValue = LibShareUtil.shareToValue(_one, _totalToken, _totalSupply);

    uint256 _price = (_underlyingTokenPrice * _ibValue) / _one;
    return (_price, _lastUpdated);
  }

  function getNonCollatId(address _account, address _token) internal pure returns (bytes32 _id) {
    _id = keccak256(abi.encodePacked(_account, _token));
  }

  function isSubaccountHealthy(address _subAccount, MoneyMarketDiamondStorage storage ds) internal view returns (bool) {
    uint256 _totalBorrowingPower = getTotalBorrowingPower(_subAccount, ds);
    (uint256 _totalUsedBorrowedPower, ) = getTotalUsedBorrowedPower(_subAccount, ds);
    return _totalBorrowingPower >= _totalUsedBorrowedPower;
  }

  function withdraw(
    address _ibToken,
    uint256 _shareAmount,
    address _withdrawFrom,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal returns (uint256 _shareValue) {
    address _token = moneyMarketDs.ibTokenToTokens[_ibToken];
    accureInterest(_token, moneyMarketDs);

    if (_token == address(0)) {
      revert LibMoneyMarket01_InvalidToken(_ibToken);
    }

    uint256 _totalSupply = ERC20(_ibToken).totalSupply();
    uint256 _tokenDecimals = ERC20(_ibToken).decimals();
    uint256 _totalToken = getTotalToken(_token, moneyMarketDs);

    _shareValue = LibShareUtil.shareToValue(_shareAmount, _totalToken, _totalSupply);

    uint256 _shareLeft = _totalSupply - _shareAmount;
    if (_shareLeft != 0 && _shareLeft < 10**(_tokenDecimals) - 1) {
      revert LibMoneyMarket01_NoTinyShares();
    }

    IIbToken(_ibToken).burn(_withdrawFrom, _shareAmount);
    ERC20(_token).safeTransfer(_withdrawFrom, _shareValue);

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
    ds.collats[_token] += _addAmount;
    ds.accountCollats[msg.sender][_token] += _addAmount;
  }

  function removeCollat(
    address _subAccount,
    address _token,
    uint256 _removeAmount,
    MoneyMarketDiamondStorage storage ds
  ) internal {
    removeCollatFromSubAccount(_subAccount, _token, _removeAmount, ds);

    ds.collats[_token] -= _removeAmount;
    ds.accountCollats[msg.sender][_token] -= _removeAmount;
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
    (uint256 _totalUsedBorrowedPower, ) = getTotalUsedBorrowedPower(_subAccount, ds);
    // violate check-effect pattern for gas optimization, will change after come up with a way that doesn't loop
    if (_totalBorrowingPower < _totalUsedBorrowedPower) {
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
  }

  function updateRewardDebt(
    address _account,
    address _token,
    int256 _amount,
    MoneyMarketDiamondStorage storage ds
  ) internal {
    if (ds.poolInfos[_token].allocPoint > 0) {
      LibMoneyMarket01.PoolInfo memory pool = LibReward.updatePool(_token, ds);
      int256 _rewardDebt = (_amount * pool.accRewardPerShare.toInt256()) /
        LibMoneyMarket01.ACC_REWARD_PRECISION.toInt256();
      ds.accountRewardDebts[_account][_token] += _rewardDebt;
    }
  }
}
