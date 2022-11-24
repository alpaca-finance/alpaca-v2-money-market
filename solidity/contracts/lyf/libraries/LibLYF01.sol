// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// libs
import { LibDoublyLinkedList } from "./LibDoublyLinkedList.sol";
import { LibUIntDoublyLinkedList } from "./LibUIntDoublyLinkedList.sol";
import { LibFullMath } from "./LibFullMath.sol";
import { LibShareUtil } from "./LibShareUtil.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";

// interfaces
import { IAlpacaV2Oracle } from "../interfaces/IAlpacaV2Oracle.sol";
import { IIbToken } from "../interfaces/IIbToken.sol";
import { IMoneyMarket } from "../interfaces/IMoneyMarket.sol";
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";

library LibLYF01 {
  using LibDoublyLinkedList for LibDoublyLinkedList.List;
  using LibUIntDoublyLinkedList for LibUIntDoublyLinkedList.List;

  // keccak256("lyf.diamond.storage");
  bytes32 internal constant LYF_STORAGE_POSITION = 0x23ec0f04376c11672050f8fa65aa7cdd1b6edcb0149eaae973a7060e7ef8f3f4;

  uint256 internal constant MAX_BPS = 10000;

  error LibLYF01_BadSubAccountId();
  error LibLYF01_PriceStale(address);

  enum AssetTier {
    UNLISTED,
    COLLATERAL,
    LP
  }

  struct TokenConfig {
    LibLYF01.AssetTier tier;
    uint16 collateralFactor;
    uint16 borrowingFactor;
    uint256 maxCollateral;
    uint256 maxBorrow;
    uint256 maxToleranceExpiredSecond;
  }

  struct LPConfig {
    address strategy;
    address masterChef;
    uint256 poolId;
  }

  struct DebtShareTokens {
    address token;
    address lpToken;
  }

  // Storage
  struct LYFDiamondStorage {
    address moneyMarket;
    IAlpacaV2Oracle oracle;
    mapping(address => uint256) collats;
    mapping(address => LibDoublyLinkedList.List) subAccountCollats;
    mapping(address => TokenConfig) tokenConfigs;
    // token => lp token => debt share id
    mapping(address => mapping(address => uint256)) debtShareIds;
    mapping(uint256 => DebtShareTokens) debtShareTokens;
    mapping(address => LibUIntDoublyLinkedList.List) subAccountDebtShares;
    mapping(uint256 => uint256) debtShares;
    mapping(uint256 => uint256) debtValues;
    mapping(uint256 => uint256) debtLastAccureTime;
    mapping(address => uint256) lpShares;
    mapping(address => uint256) lpValues;
    mapping(address => LPConfig) lpConfigs;
    mapping(uint256 => address) interestModels;
  }

  function lyfDiamondStorage() internal pure returns (LYFDiamondStorage storage lyfStorage) {
    assembly {
      lyfStorage.slot := LYF_STORAGE_POSITION
    }
  }

  function getSubAccount(address primary, uint256 subAccountId) internal pure returns (address) {
    if (subAccountId > 255) revert LibLYF01_BadSubAccountId();
    return address(uint160(primary) ^ uint160(subAccountId));
  }

  function setTokenConfig(
    address _token,
    TokenConfig memory _config,
    LYFDiamondStorage storage lyfDs
  ) internal {
    lyfDs.tokenConfigs[_token] = _config;
  }

  function pendingInterest(uint256 _debtShareId, LYFDiamondStorage storage lyfDs)
    internal
    view
    returns (uint256 _pendingInterest)
  {
    uint256 _lastAccureTime = lyfDs.debtLastAccureTime[_debtShareId];
    if (block.timestamp > _lastAccureTime) {
      uint256 _timePast = block.timestamp - _lastAccureTime;
      address _interestModel = address(lyfDs.interestModels[_debtShareId]);
      if (_interestModel != address(0)) {
        address _token = lyfDs.debtShareTokens[_debtShareId].token;
        (uint256 _debtValue, ) = IMoneyMarket(lyfDs.moneyMarket).getGlobalDebt(_token);
        uint256 _floating = IMoneyMarket(lyfDs.moneyMarket).getFloatingBalance(_token);
        uint256 _interestRate = IInterestRateModel(_interestModel).getInterestRate(_debtValue, _floating);

        _pendingInterest = (_interestRate * _timePast * lyfDs.debtValues[_debtShareId]) / 1e18;
      }
    }
  }

  function accureInterest(uint256 _debtShareId, LYFDiamondStorage storage lyfDs) internal {
    uint256 _pendingInterest = pendingInterest(_debtShareId, lyfDs);
    if (_pendingInterest > 0) {
      // update overcollat debt
      lyfDs.debtValues[_debtShareId] += _pendingInterest;
      // update timestamp
      lyfDs.debtLastAccureTime[_debtShareId] = block.timestamp;
    }
  }

  function accureAllSubAccountDebtShares(address _subAccount, LYFDiamondStorage storage lyfDs) internal {
    LibUIntDoublyLinkedList.Node[] memory _debtShares = lyfDs.subAccountDebtShares[_subAccount].getAll();
    uint256 _debtShareLength = _debtShares.length;

    for (uint256 _i = 0; _i < _debtShareLength; ) {
      accureInterest(_debtShares[_i].index, lyfDs);
      unchecked {
        _i++;
      }
    }
  }

  // TODO: handle decimal
  function getTotalBorrowingPower(address _subAccount, LYFDiamondStorage storage lyfDs)
    internal
    view
    returns (uint256 _totalBorrowingPowerUSDValue)
  {
    LibDoublyLinkedList.Node[] memory _collats = lyfDs.subAccountCollats[_subAccount].getAll();

    uint256 _collatsLength = _collats.length;

    for (uint256 _i = 0; _i < _collatsLength; ) {
      address _collatToken = _collats[_i].token;
      uint256 _collatAmount = _collats[_i].amount;
      uint256 _actualAmount = _collatAmount;

      // will return address(0) if _collatToken is not ibToken
      address _actualToken = IMoneyMarket(lyfDs.moneyMarket).ibTokenToTokens(_collatToken);
      if (_actualToken == address(0)) {
        _actualToken = _collatToken;
      } else {
        uint256 _totalSupply = IIbToken(_collatToken).totalSupply();
        uint256 _totalToken = getTotalToken(_actualToken, lyfDs);

        _actualAmount = LibShareUtil.shareToValue(_collatAmount, _totalToken, _totalSupply);
      }

      TokenConfig memory _tokenConfig = lyfDs.tokenConfigs[_collatToken];

      (uint256 _tokenPrice, ) = getPriceUSD(_collatToken, lyfDs);

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

  function getTotalUsedBorrowedPower(address _subAccount, LYFDiamondStorage storage lyfDs)
    internal
    view
    returns (uint256 _totalUsedBorrowedPower, bool _hasIsolateAsset)
  {
    // todo: debt thing
    // LibDoublyLinkedList.Node[] memory _borrowed = lyfDs.subAccountDebtShares[_subAccount].getAll();
    // uint256 _borrowedLength = _borrowed.length;
    // for (uint256 _i = 0; _i < _borrowedLength; ) {
    //   TokenConfig memory _tokenConfig = lyfDs.tokenConfigs[_borrowed[_i].token];
    //   if (_tokenConfig.tier == AssetTier.ISOLATE) {
    //     _hasIsolateAsset = true;
    //   }
    //   (uint256 _tokenPrice, ) = getPriceUSD(_borrowed[_i].token, lyfDs);
    //   uint256 _borrowedAmount = LibShareUtil.shareToValue(
    //     _borrowed[_i].amount,
    //     lyfDs.debtValues[_borrowed[_i].token],
    //     lyfDs.debtShares[_borrowed[_i].token]
    //   );
    //   _totalUsedBorrowedPower += usedBorrowedPower(_borrowedAmount, _tokenPrice, _tokenConfig.borrowingFactor);
    //   unchecked {
    //     _i++;
    //   }
    // }
  }

  function getPriceUSD(address _token, LYFDiamondStorage storage lyfDs) internal view returns (uint256, uint256) {
    (uint256 _price, uint256 _lastUpdated) = lyfDs.oracle.getTokenPrice(_token);
    if (_lastUpdated < block.timestamp - lyfDs.tokenConfigs[_token].maxToleranceExpiredSecond)
      revert LibLYF01_PriceStale(_token);
    return (_price, _lastUpdated);
  }

  // totalToken is the amount of token remains in MM + borrowed amount - collateral from user
  // where borrowed amount consists of over-collat and non-collat borrowing
  function getTotalToken(address _token, LYFDiamondStorage storage lyfDs) internal view returns (uint256) {
    // todo: think about debt
    // return (ERC20(_token).balanceOf(address(this)) + lyfDs.globalDebts[_token]) - lyfDs.collats[_token];
    return ERC20(_token).balanceOf(address(this)) - lyfDs.collats[_token];
  }

  // _usedBorrowedPower += _borrowedAmount * tokenPrice * (10000/ borrowingFactor)
  function usedBorrowedPower(
    uint256 _borrowedAmount,
    uint256 _tokenPrice,
    uint256 _borrowingFactor
  ) internal pure returns (uint256 _usedBorrowedPower) {
    _usedBorrowedPower = LibFullMath.mulDiv(_borrowedAmount * MAX_BPS, _tokenPrice, 1e18 * uint256(_borrowingFactor));
  }

  function addCollat(
    address _subAccount,
    address _token,
    uint256 _amount,
    LYFDiamondStorage storage lyfDs
  ) internal returns (uint256 _amountAdded) {
    // update subaccount state
    LibDoublyLinkedList.List storage subAccountCollateralList = lyfDs.subAccountCollats[_subAccount];
    if (subAccountCollateralList.getNextOf(LibDoublyLinkedList.START) == LibDoublyLinkedList.EMPTY) {
      subAccountCollateralList.init();
    }
    uint256 _currentAmount = subAccountCollateralList.getAmount(_token);

    _amountAdded = _amount;
    // If collat is LP take collat as a share, not direct amount
    if (lyfDs.tokenConfigs[_token].tier == AssetTier.LP) {
      _amountAdded = LibShareUtil.valueToShareRoundingUp(_amount, lyfDs.lpShares[_token], lyfDs.lpValues[_token]);

      // update lp global state
      lyfDs.lpShares[_token] += _amountAdded;
      lyfDs.lpValues[_token] += _amount;
    }

    subAccountCollateralList.addOrUpdate(_token, _currentAmount + _amountAdded);

    lyfDs.collats[_token] += _amount;
  }

  function removeCollateral(
    address _subAccount,
    address _token,
    uint256 _removeAmount,
    LYFDiamondStorage storage ds
  ) internal returns (uint256 _amountRemoved) {
    LibDoublyLinkedList.List storage _subAccountCollatList = ds.subAccountCollats[_subAccount];

    uint256 _collateralAmount = _subAccountCollatList.getAmount(_token);
    if (_collateralAmount > 0) {
      _amountRemoved = _removeAmount > _collateralAmount ? _collateralAmount : _removeAmount;

      _subAccountCollatList.updateOrRemove(_token, _collateralAmount - _amountRemoved);

      // If LP token, handle extra step
      if (ds.tokenConfigs[_token].tier == AssetTier.LP) {
        _amountRemoved = LibShareUtil.shareToValue(_removeAmount, ds.lpValues[_token], ds.lpShares[_token]);

        ds.lpShares[_token] -= _removeAmount;
        ds.lpValues[_token] -= _amountRemoved;
      }

      ds.collats[_token] -= _amountRemoved;
    }
  }

  function isSubaccountHealthy(address _subAccount, LYFDiamondStorage storage ds) internal view returns (bool) {
    uint256 _totalBorrowingPower = getTotalBorrowingPower(_subAccount, ds);
    (uint256 _totalUsedBorrowedPower, ) = getTotalUsedBorrowedPower(_subAccount, ds);
    return _totalBorrowingPower >= _totalUsedBorrowedPower;
  }
}
