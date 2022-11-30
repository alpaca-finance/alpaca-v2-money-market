// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// libs
import { LibDoublyLinkedList } from "./LibDoublyLinkedList.sol";
import { LibFullMath } from "./LibFullMath.sol";
import { LibShareUtil } from "./LibShareUtil.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";

// interfaces
import { IIbToken } from "../interfaces/IIbToken.sol";
import { IPriceOracle } from "../interfaces/IPriceOracle.sol";
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";

library LibMoneyMarket01 {
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  // keccak256("moneymarket.diamond.storage");
  bytes32 internal constant MONEY_MARKET_STORAGE_POSITION =
    0x2758c6926500ec9dc8ab8cea4053d172d4f50d9b78a6c2ee56aa5dd18d2c800b;

  uint256 internal constant MAX_BPS = 10000;
  uint256 internal constant ACC_ALPACA_PRECISION = 1e12;

  error LibMoneyMarket01_BadSubAccountId();
  error LibMoneyMarket01_PriceStale(address);

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
  }

  struct RewardConfig {
    address token;
    uint256 rewardPerSecond;
  }

  // todo: optimize type
  struct PoolInfo {
    uint256 accRewardPerShare;
    uint256 lastRewardTime;
    uint256 allocPoint;
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
    // reward stuff
    address rewardDistributor;
    mapping(address => LibDoublyLinkedList.List) accountCollats; // amount in user info
    // token => pool info
    mapping(address => PoolInfo) poolInfos;
    // account => pool key (token) => amount
    mapping(address => mapping(address => uint256)) accountRewardDebts;
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

  // TODO: handle decimal
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
        _actualAmount * _tokenConfig.collateralFactor,
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

      // todo: handle token decimals
      // _totalBorrowedUSDValue += _borrowedAmount * tokenPrice
      _totalBorrowedUSDValue += LibFullMath.mulDiv(_borrowedAmount, _tokenPrice, 1e18);

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

      // TODO: handle token decimals
      _pendingInterest = (_interestRatePerSec * _timePast * moneyMarketDs.debtValues[_token]) / 1e18;

      // non collat interest
      LibDoublyLinkedList.Node[] memory _borrowedAccounts = moneyMarketDs.nonCollatTokenDebtValues[_token].getAll();
      uint256 _accountLength = _borrowedAccounts.length;
      for (uint256 _i = 0; _i < _accountLength; ) {
        // todo: modify Node struct
        address _account = _borrowedAccounts[_i].token;

        uint256 _nonCollatInterestRate = getNonCollatInterestRate(_account, _token, moneyMarketDs);

        // TODO: handle token decimals
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
      // TODO: handle token decimals
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
      // todo: modify Node struct
      address _account = _borrowedAccounts[_i].token;
      uint256 _oldAccountDebt = _borrowedAccounts[_i].amount;

      uint256 _nonCollatInterestRate = getNonCollatInterestRate(_account, _token, moneyMarketDs);

      // TODO: handle token decimals
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
    return (ERC20(_token).balanceOf(address(this)) + moneyMarketDs.globalDebts[_token]) - moneyMarketDs.collats[_token];
  }

  function getFloatingBalance(address _token, MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _floating)
  {
    _floating = ERC20(_token).balanceOf(address(this)) - moneyMarketDs.collats[_token];
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

  function getNonCollatId(address _account, address _token) internal pure returns (bytes32 _id) {
    _id = keccak256(abi.encodePacked(_account, _token));
  }

  function isSubaccountHealthy(address _subAccount, MoneyMarketDiamondStorage storage ds) internal view returns (bool) {
    uint256 _totalBorrowingPower = getTotalBorrowingPower(_subAccount, ds);
    (uint256 _totalUsedBorrowedPower, ) = getTotalUsedBorrowedPower(_subAccount, ds);
    return _totalBorrowingPower >= _totalUsedBorrowedPower;
  }
}
