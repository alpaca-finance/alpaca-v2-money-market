// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
import { IMasterChefLike } from "../interfaces/IMasterChefLike.sol";
import { IRouterLike } from "../interfaces/IRouterLike.sol";
import { ISwapPairLike } from "../interfaces/ISwapPairLike.sol";
import { IStrat } from "../interfaces/IStrat.sol";

library LibLYF01 {
  using LibDoublyLinkedList for LibDoublyLinkedList.List;
  using LibUIntDoublyLinkedList for LibUIntDoublyLinkedList.List;
  using SafeERC20 for ERC20;

  // keccak256("lyf.diamond.storage");
  bytes32 internal constant LYF_STORAGE_POSITION = 0x23ec0f04376c11672050f8fa65aa7cdd1b6edcb0149eaae973a7060e7ef8f3f4;

  uint256 internal constant MAX_BPS = 10000;

  event LogReinvest(address indexed _rewardTo, uint256 _reward, uint256 _bounty);

  error LibLYF01_BadSubAccountId();
  error LibLYF01_PriceStale(address);
  error LibLYF01_UnsupportedDecimals();

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
    uint8 to18ConversionFactor;
  }

  struct LPConfig {
    address strategy;
    address masterChef;
    address router;
    address rewardToken;
    address[] reinvestPath;
    uint256 poolId;
    uint256 reinvestThreshold;
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
    mapping(address => uint256) pendingRewards;
    mapping(address => bool) reinvestorsOk;
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

      TokenConfig memory _tokenConfig = lyfDs.tokenConfigs[_actualToken];

      (uint256 _tokenPrice, ) = getPriceUSD(_actualToken, lyfDs);

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

  function getTotalUsedBorrowedPower(address _subAccount, LYFDiamondStorage storage lyfDs)
    internal
    view
    returns (uint256 _totalUsedBorrowedPower)
  {
    LibUIntDoublyLinkedList.Node[] memory _borrowed = lyfDs.subAccountDebtShares[_subAccount].getAll();
    uint256 _borrowedLength = _borrowed.length;
    for (uint256 _i = 0; _i < _borrowedLength; ) {
      address _debtToken = lyfDs.debtShareTokens[_borrowed[_i].index].token;
      TokenConfig memory _tokenConfig = lyfDs.tokenConfigs[_debtToken];
      (uint256 _tokenPrice, ) = getPriceUSD(_debtToken, lyfDs);
      uint256 _borrowedAmount = LibShareUtil.shareToValue(
        _borrowed[_i].amount,
        lyfDs.debtValues[_borrowed[_i].index],
        lyfDs.debtShares[_borrowed[_i].index]
      );
      _totalUsedBorrowedPower += usedBorrowedPower(_borrowedAmount, _tokenPrice, _tokenConfig.borrowingFactor);
      unchecked {
        _i++;
      }
    }
  }

  function getPriceUSD(address _token, LYFDiamondStorage storage lyfDs)
    internal
    view
    returns (uint256 _price, uint256 _lastUpdated)
  {
    if (lyfDs.tokenConfigs[_token].tier == AssetTier.LP) {
      (_price, _lastUpdated) = lyfDs.oracle.lpToDollar(1e18, _token);
    } else {
      (_price, _lastUpdated) = lyfDs.oracle.getTokenPrice(_token);
    }
    if (_lastUpdated < block.timestamp - lyfDs.tokenConfigs[_token].maxToleranceExpiredSecond)
      revert LibLYF01_PriceStale(_token);
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
      reinvest(_token, lyfDs.lpConfigs[_token].reinvestThreshold, lyfDs.lpConfigs[_token], lyfDs);

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
        reinvest(_token, ds.lpConfigs[_token].reinvestThreshold, ds.lpConfigs[_token], ds);

        _amountRemoved = LibShareUtil.shareToValue(_removeAmount, ds.lpValues[_token], ds.lpShares[_token]);

        ds.lpShares[_token] -= _removeAmount;
        ds.lpValues[_token] -= _amountRemoved;
      }

      ds.collats[_token] -= _amountRemoved;
    }
  }

  function removeIbCollateral(
    address _subAccount,
    address _token,
    address _ibToken,
    uint256 _removeAmountUnderlying,
    LYFDiamondStorage storage ds
  ) internal returns (uint256 _underlyingRemoved) {
    if (_ibToken == address(0) || _removeAmountUnderlying == 0) return 0;

    LibDoublyLinkedList.List storage _subAccountCollatList = ds.subAccountCollats[_subAccount];

    uint256 _collateralAmountIb = _subAccountCollatList.getAmount(_ibToken);

    if (_collateralAmountIb > 0) {
      IMoneyMarket moneyMarket = IMoneyMarket(ds.moneyMarket);

      uint256 _removeAmountIb = moneyMarket.getIbShareFromUnderlyingAmount(_token, _removeAmountUnderlying);
      uint256 _ibRemoved = _removeAmountIb > _collateralAmountIb ? _collateralAmountIb : _removeAmountIb;

      _subAccountCollatList.updateOrRemove(_ibToken, _collateralAmountIb - _ibRemoved);

      _underlyingRemoved = moneyMarket.withdraw(_ibToken, _ibRemoved);

      ds.collats[_ibToken] -= _ibRemoved;
    }
  }

  function isSubaccountHealthy(address _subAccount, LYFDiamondStorage storage ds) internal view returns (bool) {
    uint256 _totalBorrowingPower = getTotalBorrowingPower(_subAccount, ds);
    uint256 _totalUsedBorrowedPower = getTotalUsedBorrowedPower(_subAccount, ds);
    return _totalBorrowingPower >= _totalUsedBorrowedPower;
  }

  function to18ConversionFactor(address _token) internal view returns (uint8) {
    uint256 _decimals = ERC20(_token).decimals();
    if (_decimals > 18) revert LibLYF01_UnsupportedDecimals();
    uint256 _conversionFactor = 10**(18 - _decimals);
    return uint8(_conversionFactor);
  }

  function depositToMasterChef(
    address _lpToken,
    LibLYF01.LPConfig memory _lpconfig,
    uint256 _amount
  ) internal {
    ERC20(_lpToken).safeApprove(_lpconfig.masterChef, type(uint256).max);
    IMasterChefLike(_lpconfig.masterChef).deposit(_lpconfig.poolId, _amount);
    ERC20(_lpToken).safeApprove(_lpconfig.masterChef, 0);
  }

  function harvest(
    address _lpToken,
    LibLYF01.LPConfig memory _lpConfig,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal {
    uint256 _rewardBefore = ERC20(_lpConfig.rewardToken).balanceOf(address(this));

    IMasterChefLike(_lpConfig.masterChef).withdraw(_lpConfig.poolId, 0);

    // accumulate harvested reward for LP
    lyfDs.pendingRewards[_lpToken] += ERC20(_lpConfig.rewardToken).balanceOf(address(this)) - _rewardBefore;
  }

  function reinvest(
    address _lpToken,
    uint256 _reinvestThreshold,
    LibLYF01.LPConfig memory _lpConfig,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal {
    harvest(_lpToken, _lpConfig, lyfDs);

    uint256 _rewardAmount = lyfDs.pendingRewards[_lpToken];
    if (_rewardAmount < _reinvestThreshold) return;

    // TODO: extract fee

    address _token0 = ISwapPairLike(_lpToken).token0();
    address _token1 = ISwapPairLike(_lpToken).token1();

    // convert rewardToken to either token0 or token1
    uint256 _reinvestAmount = 0;
    if (_lpConfig.rewardToken == _token0 || _lpConfig.rewardToken == _token1) {
      _reinvestAmount = _rewardAmount;
    } else {
      ERC20(_lpConfig.rewardToken).safeApprove(_lpConfig.router, _rewardAmount);
      uint256[] memory _amounts = IRouterLike(_lpConfig.router).swapExactTokensForTokens(
        _rewardAmount,
        0,
        _lpConfig.reinvestPath,
        address(this),
        block.timestamp
      );
      _reinvestAmount = _amounts[_amounts.length - 1];
    }

    uint256 _token0Amount;
    uint256 _token1Amount;
    address _reinvestToken = _lpConfig.reinvestPath[_lpConfig.reinvestPath.length - 1];

    if (_reinvestToken == _token0) {
      _token0Amount = _reinvestAmount;
    } else {
      _token1Amount = _reinvestAmount;
    }

    ERC20(_token0).safeTransfer(_lpConfig.strategy, _token0Amount);
    ERC20(_token1).safeTransfer(_lpConfig.strategy, _token1Amount);
    uint256 _lpReceived = IStrat(_lpConfig.strategy).composeLPToken(
      _token0,
      _token1,
      _lpToken,
      _token0Amount,
      _token1Amount,
      0
    );

    // deposit lp back to masterChef
    lyfDs.lpValues[_lpToken] += _lpReceived;
    depositToMasterChef(_lpToken, _lpConfig, _lpReceived);

    // reset pending reward
    lyfDs.pendingRewards[_lpToken] = 0;

    // TODO: assign param properly
    emit LogReinvest(msg.sender, 0, 0);
  }
}
