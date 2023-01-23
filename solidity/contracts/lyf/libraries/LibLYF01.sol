// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// libs
import { LibDoublyLinkedList } from "./LibDoublyLinkedList.sol";
import { LibUIntDoublyLinkedList } from "./LibUIntDoublyLinkedList.sol";
import { LibFullMath } from "./LibFullMath.sol";
import { LibShareUtil } from "./LibShareUtil.sol";
import { LibSafeToken } from "./LibSafeToken.sol";

// interfaces
import { IAlpacaV2Oracle } from "../interfaces/IAlpacaV2Oracle.sol";
import { IMoneyMarket } from "../interfaces/IMoneyMarket.sol";
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";
import { IMasterChefLike } from "../interfaces/IMasterChefLike.sol";
import { IRouterLike } from "../interfaces/IRouterLike.sol";
import { ISwapPairLike } from "../interfaces/ISwapPairLike.sol";
import { IStrat } from "../interfaces/IStrat.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

library LibLYF01 {
  using LibDoublyLinkedList for LibDoublyLinkedList.List;
  using LibUIntDoublyLinkedList for LibUIntDoublyLinkedList.List;
  using LibSafeToken for IERC20;

  // keccak256("lyf.diamond.storage");
  bytes32 internal constant LYF_STORAGE_POSITION = 0x23ec0f04376c11672050f8fa65aa7cdd1b6edcb0149eaae973a7060e7ef8f3f4;

  uint256 internal constant MAX_BPS = 10000;

  event LogAccrueInterest(address indexed _token, uint256 _totalInterest, uint256 _totalToProtocolReserve);
  event LogReinvest(address indexed _rewardTo, uint256 _reward, uint256 _bounty);

  error LibLYF01_BadSubAccountId();
  error LibLYF01_PriceStale(address);
  error LibLYF01_UnsupportedDecimals();
  error LibLYF01_NumberOfTokenExceedLimit();
  error LibLYF01_BorrowLessThanMinDebtSize();
  error LibLYF01_BadDebtShareId();
  error LibLYF01_LPCollateralExceedLimit();

  enum AssetTier {
    UNLISTED,
    COLLATERAL,
    LP
  }

  struct TokenConfig {
    LibLYF01.AssetTier tier;
    uint16 collateralFactor;
    uint16 borrowingFactor;
    uint64 to18ConversionFactor;
    uint256 maxCollateral;
  }

  struct LPConfig {
    address strategy;
    address masterChef;
    address router;
    address rewardToken;
    address[] reinvestPath;
    uint256 poolId;
    uint256 reinvestThreshold;
    uint256 globalMaxCollatAmount;
  }

  // Storage
  struct LYFDiamondStorage {
    IMoneyMarket moneyMarket;
    IAlpacaV2Oracle oracle;
    address treasury;
    // ---- protocol parameters ---- //
    uint8 maxNumOfCollatPerSubAccount; // maximum number of token in the collat linked list
    uint8 maxNumOfDebtPerSubAccount; // maximum number of token in the debt linked list
    uint256 minDebtSize; // minimum USD value that debt position must maintain
    // ---- reserves ---- //
    mapping(address => uint256) reserves; // track token balance of protocol
    mapping(address => uint256) protocolReserves; // part of reserves that belongs to protocol
    // collats = amount of collateral token
    mapping(address => uint256) collats;
    // ---- subAccounts ---- //
    mapping(address => LibDoublyLinkedList.List) subAccountCollats; // subAccount => linked list of collats
    mapping(address => LibUIntDoublyLinkedList.List) subAccountDebtShares; // subAccount => linked list of debtShares
    // ---- tokens ---- //
    mapping(address => TokenConfig) tokenConfigs; // arbitrary token => config
    // ---- debtShareIds ---- //
    mapping(address => mapping(address => uint256)) debtShareIds; // token => lp token => debt share id
    mapping(uint256 => address) debtShareTokens; // debtShareId => token
    mapping(uint256 => uint256) debtShares; // debtShareId => debt share
    mapping(uint256 => uint256) debtValues; // debtShareId => debt value
    mapping(uint256 => uint256) debtLastAccrueTime; // debtShareId => last debt accrual timestamp
    mapping(uint256 => address) interestModels; // debtShareId => interest model
    // ---- lpTokens ---- //
    mapping(address => uint256) lpShares; // lpToken => total share that in protocol's control (collat + farm)
    mapping(address => uint256) lpAmounts; // lpToken => total amount that in protocol's control (collat + farm)
    mapping(address => LPConfig) lpConfigs; // lpToken => config
    mapping(address => uint256) pendingRewards; // lpToken => pending reward amount to be reinvested
    // ---- whitelists ---- //
    mapping(address => bool) reinvestorsOk; // address that can call reinvest
    mapping(address => bool) liquidationStratOk; // liquidation strategies that can be called during liquidation process
    mapping(address => bool) liquidationCallersOk; // address that can initiate liquidation process
  }

  function lyfDiamondStorage() internal pure returns (LYFDiamondStorage storage lyfStorage) {
    assembly {
      lyfStorage.slot := LYF_STORAGE_POSITION
    }
  }

  function getSubAccount(address _primary, uint256 _subAccountId) internal pure returns (address) {
    if (_subAccountId > 255) {
      revert LibLYF01_BadSubAccountId();
    }
    return address(uint160(_primary) ^ uint160(_subAccountId));
  }

  function getDebtSharePendingInterest(
    IMoneyMarket _moneyMarket,
    address _interestModel,
    address _token,
    uint256 _secondsSinceLastAccrual,
    uint256 _debtShareDebtValue
  ) internal view returns (uint256 _pendingInterest) {
    uint256 _mmDebtValue = _moneyMarket.getGlobalDebtValue(_token);
    uint256 _floating = _moneyMarket.getFloatingBalance(_token);
    uint256 _interestRate = IInterestRateModel(_interestModel).getInterestRate(_mmDebtValue, _floating);
    _pendingInterest = (_interestRate * _secondsSinceLastAccrual * _debtShareDebtValue) / 1e18;
  }

  function accrueDebtShareInterest(uint256 _debtShareId, LYFDiamondStorage storage lyfDs) internal {
    uint256 _secondsSinceLastAccrual = block.timestamp - lyfDs.debtLastAccrueTime[_debtShareId];
    if (_secondsSinceLastAccrual > 0) {
      uint256 _pendingInterest = getDebtSharePendingInterest(
        lyfDs.moneyMarket,
        lyfDs.interestModels[_debtShareId],
        lyfDs.debtShareTokens[_debtShareId],
        _secondsSinceLastAccrual,
        lyfDs.debtValues[_debtShareId]
      );

      lyfDs.debtValues[_debtShareId] += _pendingInterest;
      lyfDs.protocolReserves[lyfDs.debtShareTokens[_debtShareId]] += _pendingInterest;
      lyfDs.debtLastAccrueTime[_debtShareId] = block.timestamp;

      emit LogAccrueInterest(lyfDs.debtShareTokens[_debtShareId], _pendingInterest, _pendingInterest);
    }
  }

  function accrueDebtSharesOf(address _subAccount, LYFDiamondStorage storage lyfDs) internal {
    LibUIntDoublyLinkedList.Node[] memory _debtShares = lyfDs.subAccountDebtShares[_subAccount].getAll();
    uint256 _debtShareLength = _debtShares.length;

    for (uint256 _i; _i < _debtShareLength; ) {
      accrueDebtShareInterest(_debtShares[_i].index, lyfDs);
      unchecked {
        ++_i;
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

    address _collatToken;
    address _underlyingToken;
    uint256 _collatPrice;
    TokenConfig memory _tokenConfig;
    IMoneyMarket _moneyMarket = lyfDs.moneyMarket;

    for (uint256 _i; _i < _collatsLength; ) {
      _collatToken = _collats[_i].token;

      _underlyingToken = _moneyMarket.getTokenFromIbToken(_collatToken);
      if (_underlyingToken != address(0)) {
        // if _collatToken is ibToken convert underlying price to ib price
        _tokenConfig = lyfDs.tokenConfigs[_underlyingToken];
        _collatPrice =
          (getPriceUSD(_underlyingToken, lyfDs) *
            getIbToUnderlyingConversionFactor(_collatToken, _underlyingToken, _moneyMarket)) /
          1e18;
      } else {
        // _collatToken is normal ERC20 or LP token
        _tokenConfig = lyfDs.tokenConfigs[_collatToken];
        _collatPrice = getPriceUSD(_collatToken, lyfDs);
      }

      // _totalBorrowingPowerUSDValue += collatAmount * collatPrice * collateralFactor
      _totalBorrowingPowerUSDValue += LibFullMath.mulDiv(
        _collats[_i].amount * _tokenConfig.to18ConversionFactor * _tokenConfig.collateralFactor,
        _collatPrice,
        1e22
      );

      unchecked {
        ++_i;
      }
    }
  }

  function getTotalUsedBorrowingPower(address _subAccount, LYFDiamondStorage storage lyfDs)
    internal
    view
    returns (uint256 _totalUsedBorrowingPower)
  {
    LibUIntDoublyLinkedList.Node[] memory _borrowed = lyfDs.subAccountDebtShares[_subAccount].getAll();

    uint256 _borrowedLength = _borrowed.length;

    TokenConfig memory _tokenConfig;
    address _debtToken;

    for (uint256 _i; _i < _borrowedLength; ) {
      _debtToken = lyfDs.debtShareTokens[_borrowed[_i].index];
      _tokenConfig = lyfDs.tokenConfigs[_debtToken];
      _totalUsedBorrowingPower += usedBorrowingPower(
        LibShareUtil.shareToValue(
          _borrowed[_i].amount,
          lyfDs.debtValues[_borrowed[_i].index],
          lyfDs.debtShares[_borrowed[_i].index]
        ),
        getPriceUSD(_debtToken, lyfDs),
        _tokenConfig.borrowingFactor,
        _tokenConfig.to18ConversionFactor
      );
      unchecked {
        ++_i;
      }
    }
  }

  function getTotalBorrowedUSDValue(address _subAccount, LYFDiamondStorage storage lyfDs)
    internal
    view
    returns (uint256 _totalBorrowedUSDValue)
  {
    LibUIntDoublyLinkedList.Node[] memory _borrowed = lyfDs.subAccountDebtShares[_subAccount].getAll();

    uint256 _borrowedLength = _borrowed.length;
    address _debtToken;

    for (uint256 _i; _i < _borrowedLength; ) {
      _debtToken = lyfDs.debtShareTokens[_borrowed[_i].index];

      // _totalBorrowedUSDValue += _borrowedAmount * tokenPrice
      _totalBorrowedUSDValue += LibFullMath.mulDiv(
        LibShareUtil.shareToValue(
          _borrowed[_i].amount,
          lyfDs.debtValues[_borrowed[_i].index],
          lyfDs.debtShares[_borrowed[_i].index]
        ) * lyfDs.tokenConfigs[_debtToken].to18ConversionFactor,
        getPriceUSD(_debtToken, lyfDs),
        1e18
      );

      unchecked {
        ++_i;
      }
    }
  }

  function getPriceUSD(address _token, LYFDiamondStorage storage lyfDs) internal view returns (uint256 _price) {
    if (lyfDs.tokenConfigs[_token].tier == AssetTier.LP) {
      (_price, ) = lyfDs.oracle.lpToDollar(1e18, _token);
    } else {
      (_price, ) = lyfDs.oracle.getTokenPrice(_token);
    }
  }

  /// @dev ex. 1 ib = 1.2 token -> conversionFactor = 1.2
  /// ibPrice = (underlyingPrice * conversionFactor) / 1e18
  /// ibAmount = (underlyingAmount * 1e18) / conversionFactor
  function getIbToUnderlyingConversionFactor(
    address _ibToken,
    address _underlyingToken,
    IMoneyMarket _moneyMarket
  ) internal view returns (uint256 _conversionFactor) {
    uint256 _totalSupply = IERC20(_ibToken).totalSupply();
    uint256 _decimals = IERC20(_ibToken).decimals();
    uint256 _totalToken = _moneyMarket.getTotalTokenWithPendingInterest(_underlyingToken);
    _conversionFactor = LibShareUtil.shareToValue(10**_decimals, _totalToken, _totalSupply);
  }

  // _usedBorrowingPower += _borrowedAmount * tokenPrice * (10000/ borrowingFactor)
  function usedBorrowingPower(
    uint256 _borrowedAmount,
    uint256 _tokenPrice,
    uint256 _borrowingFactor,
    uint256 _to18ConversionFactor
  ) internal pure returns (uint256 _usedBorrowingPower) {
    _usedBorrowingPower = LibFullMath.mulDiv(
      _borrowedAmount * MAX_BPS * _to18ConversionFactor,
      _tokenPrice,
      1e18 * uint256(_borrowingFactor)
    );
  }

  function addCollat(
    address _subAccount,
    address _token,
    uint256 _amount,
    LYFDiamondStorage storage lyfDs
  ) internal returns (uint256 _amountAdded) {
    _amountAdded = _addCollat(_subAccount, _token, _amount, lyfDs);
    if (lyfDs.subAccountCollats[_subAccount].length() > lyfDs.maxNumOfCollatPerSubAccount) {
      revert LibLYF01_NumberOfTokenExceedLimit();
    }
  }

  function addCollatWithoutMaxCollatNumCheck(
    address _subAccount,
    address _token,
    uint256 _amount,
    LYFDiamondStorage storage lyfDs
  ) internal returns (uint256 _amountAdded) {
    _amountAdded = _addCollat(_subAccount, _token, _amount, lyfDs);
  }

  function _addCollat(
    address _subAccount,
    address _token,
    uint256 _amount,
    LYFDiamondStorage storage lyfDs
  ) private returns (uint256 _amountAdded) {
    // update subaccount state
    LibDoublyLinkedList.List storage subAccountCollateralList = lyfDs.subAccountCollats[_subAccount];
    subAccountCollateralList.initIfNotExist();

    uint256 _currentAmount = subAccountCollateralList.getAmount(_token);

    _amountAdded = _amount;
    // If collat is LP take collat as a share, not direct amount
    if (lyfDs.tokenConfigs[_token].tier == AssetTier.LP) {
      LPConfig memory _lpConfig = lyfDs.lpConfigs[_token];

      if (lyfDs.lpAmounts[_token] + _amountAdded > _lpConfig.globalMaxCollatAmount) {
        revert LibLYF01_LPCollateralExceedLimit();
      }

      reinvest(_token, _lpConfig.reinvestThreshold, _lpConfig, lyfDs);

      // cache to save gas
      uint256 _lpAmount = lyfDs.lpAmounts[_token];
      uint256 _lpShare = lyfDs.lpShares[_token];

      _amountAdded = LibShareUtil.valueToShare(_amount, _lpShare, _lpAmount);

      // update lp global state
      lyfDs.lpShares[_token] = _lpShare + _amountAdded;
      lyfDs.lpAmounts[_token] = _lpAmount + _amount;
    }

    // update subAccount collat
    subAccountCollateralList.addOrUpdate(_token, _currentAmount + _amountAdded);

    // update global collat
    lyfDs.collats[_token] += _amount;
  }

  function removeCollateral(
    address _subAccount,
    address _token,
    uint256 _removeAmount,
    LYFDiamondStorage storage ds
  ) internal returns (uint256 _amountRemoved) {
    LibDoublyLinkedList.List storage _subAccountCollatList = ds.subAccountCollats[_subAccount];

    if (_subAccountCollatList.has(_token)) {
      uint256 _collateralAmount = _subAccountCollatList.getAmount(_token);
      _amountRemoved = _removeAmount > _collateralAmount ? _collateralAmount : _removeAmount;

      _subAccountCollatList.updateOrRemove(_token, _collateralAmount - _amountRemoved);

      // If LP token, handle extra step
      if (ds.tokenConfigs[_token].tier == AssetTier.LP) {
        reinvest(_token, ds.lpConfigs[_token].reinvestThreshold, ds.lpConfigs[_token], ds);

        uint256 _lpValueRemoved = LibShareUtil.shareToValue(_amountRemoved, ds.lpAmounts[_token], ds.lpShares[_token]);

        ds.lpShares[_token] -= _amountRemoved;
        ds.lpAmounts[_token] -= _lpValueRemoved;

        // _amountRemoved used to represent lpShare, we need to return lpValue so re-assign it here
        _amountRemoved = _lpValueRemoved;
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
    if (_ibToken == address(0) || _removeAmountUnderlying == 0) {
      return 0;
    }

    LibDoublyLinkedList.List storage _subAccountCollatList = ds.subAccountCollats[_subAccount];

    uint256 _collateralAmountIb = _subAccountCollatList.getAmount(_ibToken);

    if (_collateralAmountIb > 0) {
      IMoneyMarket moneyMarket = IMoneyMarket(ds.moneyMarket);

      uint256 _removeAmountIb = LibShareUtil.valueToShare(
        _removeAmountUnderlying,
        IERC20(_ibToken).totalSupply(),
        ds.moneyMarket.getTotalTokenWithPendingInterest(_token)
      );

      uint256 _ibRemoved = _removeAmountIb > _collateralAmountIb ? _collateralAmountIb : _removeAmountIb;

      _subAccountCollatList.updateOrRemove(_ibToken, _collateralAmountIb - _ibRemoved);

      _underlyingRemoved = moneyMarket.withdraw(_ibToken, _ibRemoved);

      ds.collats[_ibToken] -= _ibRemoved;
    }
  }

  function isSubaccountHealthy(address _subAccount, LYFDiamondStorage storage ds) internal view returns (bool) {
    uint256 _totalBorrowingPower = getTotalBorrowingPower(_subAccount, ds);
    uint256 _totalUsedBorrowingPower = getTotalUsedBorrowingPower(_subAccount, ds);
    return _totalBorrowingPower >= _totalUsedBorrowingPower;
  }

  function validateMinDebtSize(
    address _subAccount,
    uint256 _debtShareId,
    LYFDiamondStorage storage lyfDs
  ) internal view {
    // note: precision loss 1 wei when convert share back to value
    uint256 _debtAmount = LibShareUtil.shareToValue(
      lyfDs.subAccountDebtShares[_subAccount].getAmount(_debtShareId),
      lyfDs.debtValues[_debtShareId],
      lyfDs.debtShares[_debtShareId]
    );
    if (_debtAmount != 0) {
      address _debtToken = lyfDs.debtShareTokens[_debtShareId];
      uint256 _tokenPrice = getPriceUSD(_debtToken, lyfDs);

      if (
        LibFullMath.mulDiv(_debtAmount * lyfDs.tokenConfigs[_debtToken].to18ConversionFactor, _tokenPrice, 1e18) <
        lyfDs.minDebtSize
      ) {
        revert LibLYF01_BorrowLessThanMinDebtSize();
      }
    }
  }

  function to18ConversionFactor(address _token) internal view returns (uint64) {
    uint256 _decimals = IERC20(_token).decimals();
    if (_decimals > 18) {
      revert LibLYF01_UnsupportedDecimals();
    }
    uint256 _conversionFactor = 10**(18 - _decimals);
    return uint64(_conversionFactor);
  }

  function depositToMasterChef(
    address _lpToken,
    address _masterChef,
    uint256 _poolId,
    uint256 _amount
  ) internal {
    IERC20(_lpToken).safeIncreaseAllowance(_masterChef, _amount);
    IMasterChefLike(_masterChef).deposit(_poolId, _amount);
  }

  function harvest(
    address _lpToken,
    LibLYF01.LPConfig memory _lpConfig,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal {
    uint256 _rewardBefore = IERC20(_lpConfig.rewardToken).balanceOf(address(this));

    IMasterChefLike(_lpConfig.masterChef).withdraw(_lpConfig.poolId, 0);

    // accumulate harvested reward for LP
    lyfDs.pendingRewards[_lpToken] += IERC20(_lpConfig.rewardToken).balanceOf(address(this)) - _rewardBefore;
  }

  function reinvest(
    address _lpToken,
    uint256 _reinvestThreshold,
    LibLYF01.LPConfig memory _lpConfig,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal {
    harvest(_lpToken, _lpConfig, lyfDs);

    uint256 _rewardAmount = lyfDs.pendingRewards[_lpToken];
    if (_rewardAmount < _reinvestThreshold) {
      return;
    }

    // TODO: extract fee

    address _token0 = ISwapPairLike(_lpToken).token0();
    address _token1 = ISwapPairLike(_lpToken).token1();

    // convert rewardToken to either token0 or token1
    uint256 _reinvestAmount;
    if (_lpConfig.rewardToken == _token0 || _lpConfig.rewardToken == _token1) {
      _reinvestAmount = _rewardAmount;
    } else {
      IERC20(_lpConfig.rewardToken).safeIncreaseAllowance(_lpConfig.router, _rewardAmount);
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

    IERC20(_token0).safeTransfer(_lpConfig.strategy, _token0Amount);
    IERC20(_token1).safeTransfer(_lpConfig.strategy, _token1Amount);
    uint256 _lpReceived = IStrat(_lpConfig.strategy).composeLPToken(
      _token0,
      _token1,
      _lpToken,
      _token0Amount,
      _token1Amount,
      0
    );

    // deposit lp back to masterChef
    lyfDs.lpAmounts[_lpToken] += _lpReceived;
    lyfDs.collats[_lpToken] += _lpReceived;
    depositToMasterChef(_lpToken, _lpConfig.masterChef, _lpConfig.poolId, _lpReceived);

    // reset pending reward
    lyfDs.pendingRewards[_lpToken] = 0;

    // TODO: assign param properly
    emit LogReinvest(msg.sender, 0, 0);
  }

  function borrow(
    address _subAccount,
    address _token,
    address _lpToken,
    uint256 _amount,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal {
    if (_amount == 0) return;
    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];
    if (_debtShareId == 0) {
      revert LibLYF01_BadDebtShareId();
    }

    LibUIntDoublyLinkedList.List storage userDebtShare = lyfDs.subAccountDebtShares[_subAccount];

    userDebtShare.initIfNotExist();

    // use reserve if it is enough, else borrow from mm entirely
    if (lyfDs.reserves[_token] - lyfDs.protocolReserves[_token] >= _amount) {
      lyfDs.reserves[_token] -= _amount;
    } else {
      IMoneyMarket(lyfDs.moneyMarket).nonCollatBorrow(_token, _amount);
    }

    uint256 _shareToAdd = LibShareUtil.valueToShareRoundingUp(
      _amount,
      lyfDs.debtShares[_debtShareId],
      lyfDs.debtValues[_debtShareId]
    );

    // update over collat debt
    lyfDs.debtShares[_debtShareId] += _shareToAdd;
    lyfDs.debtValues[_debtShareId] += _amount;

    uint256 _newShareAmount = userDebtShare.getAmount(_debtShareId) + _shareToAdd;

    // update user's debtshare
    userDebtShare.addOrUpdate(_debtShareId, _newShareAmount);

    if (userDebtShare.length() > lyfDs.maxNumOfDebtPerSubAccount) {
      revert LibLYF01_NumberOfTokenExceedLimit();
    }
  }
}
