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
  error LibLYF01_BadDebtPoolId();
  error LibLYF01_LPCollateralExceedLimit();
  error LibLYF01_FeeOnTransferTokensNotSupported();

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
    uint256 maxLpAmount;
    uint256 reinvestTreasuryBountyBps;
  }

  struct DebtPoolInfo {
    address token;
    address interestModel;
    uint256 totalShare;
    uint256 totalValue;
    uint256 lastAccruedAt;
  }

  // Storage
  struct LYFDiamondStorage {
    IMoneyMarket moneyMarket;
    IAlpacaV2Oracle oracle;
    address liquidationTreasury;
    address revenueTreasury;
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
    // ---- debtPools ---- //
    mapping(address => mapping(address => uint256)) debtPoolIds; // token => lp token => debtPoolId
    mapping(uint256 => DebtPoolInfo) debtPoolInfos; // debtPoolId => DebtPoolInfo
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

  function getDebtPoolPendingInterest(
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

  function accrueDebtPoolInterest(uint256 _debtPoolId, LYFDiamondStorage storage lyfDs) internal {
    // uint256 _secondsSinceLastAccrual = block.timestamp - lyfDs.debtLastAccrueTime[_debtPoolId];
    DebtPoolInfo storage debtPoolInfo = lyfDs.debtPoolInfos[_debtPoolId];
    uint256 _secondsSinceLastAccrual = block.timestamp - debtPoolInfo.lastAccruedAt;
    if (_secondsSinceLastAccrual > 0) {
      uint256 _pendingInterest = getDebtPoolPendingInterest(
        lyfDs.moneyMarket,
        debtPoolInfo.interestModel,
        debtPoolInfo.token,
        _secondsSinceLastAccrual,
        debtPoolInfo.totalValue
      );

      debtPoolInfo.totalValue += _pendingInterest;
      lyfDs.protocolReserves[debtPoolInfo.token] += _pendingInterest;
      debtPoolInfo.lastAccruedAt = block.timestamp;

      emit LogAccrueInterest(debtPoolInfo.token, _pendingInterest, _pendingInterest);
    }
  }

  function accrueDebtSharesOf(address _subAccount, LYFDiamondStorage storage lyfDs) internal {
    LibUIntDoublyLinkedList.Node[] memory _debtShares = lyfDs.subAccountDebtShares[_subAccount].getAll();
    uint256 _debtShareLength = _debtShares.length;

    for (uint256 _i; _i < _debtShareLength; ) {
      accrueDebtPoolInterest(_debtShares[_i].index, lyfDs);
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
    DebtPoolInfo memory _debtPooInfo;

    for (uint256 _i; _i < _borrowedLength; ) {
      _debtPooInfo = lyfDs.debtPoolInfos[_borrowed[_i].index];
      _tokenConfig = lyfDs.tokenConfigs[_debtPooInfo.token];
      _totalUsedBorrowingPower += usedBorrowingPower(
        LibShareUtil.shareToValue(_borrowed[_i].amount, _debtPooInfo.totalValue, _debtPooInfo.totalShare),
        getPriceUSD(_debtPooInfo.token, lyfDs),
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

    DebtPoolInfo memory _debtPooInfo;

    for (uint256 _i; _i < _borrowedLength; ) {
      _debtPooInfo = lyfDs.debtPoolInfos[_borrowed[_i].index];

      // _totalBorrowedUSDValue += _borrowedAmount * tokenPrice
      _totalBorrowedUSDValue += LibFullMath.mulDiv(
        LibShareUtil.shareToValue(_borrowed[_i].amount, _debtPooInfo.totalValue, _debtPooInfo.totalShare) *
          lyfDs.tokenConfigs[_debtPooInfo.token].to18ConversionFactor,
        getPriceUSD(_debtPooInfo.token, lyfDs),
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

      if (lyfDs.lpAmounts[_token] + _amountAdded > _lpConfig.maxLpAmount) {
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
    LYFDiamondStorage storage lyfDs
  ) internal returns (uint256 _amountRemoved) {
    LibDoublyLinkedList.List storage _subAccountCollatList = lyfDs.subAccountCollats[_subAccount];

    if (_subAccountCollatList.has(_token)) {
      uint256 _collateralAmount = _subAccountCollatList.getAmount(_token);
      _amountRemoved = _removeAmount > _collateralAmount ? _collateralAmount : _removeAmount;

      _subAccountCollatList.updateOrRemove(_token, _collateralAmount - _amountRemoved);

      // If LP token, handle extra step
      if (lyfDs.tokenConfigs[_token].tier == AssetTier.LP) {
        reinvest(_token, lyfDs.lpConfigs[_token].reinvestThreshold, lyfDs.lpConfigs[_token], lyfDs);

        uint256 _lpValueRemoved = LibShareUtil.shareToValue(
          _amountRemoved,
          lyfDs.lpAmounts[_token],
          lyfDs.lpShares[_token]
        );

        lyfDs.lpShares[_token] -= _amountRemoved;
        lyfDs.lpAmounts[_token] -= _lpValueRemoved;

        // _amountRemoved used to represent lpShare, we need to return lpValue so re-assign it here
        _amountRemoved = _lpValueRemoved;
      }

      lyfDs.collats[_token] -= _amountRemoved;
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
    uint256 _debtPoolId,
    LYFDiamondStorage storage lyfDs
  ) internal view {
    // note: precision loss 1 wei when convert share back to value
    DebtPoolInfo memory _debtPooInfo = lyfDs.debtPoolInfos[_debtPoolId];
    uint256 _debtAmount = LibShareUtil.shareToValue(
      lyfDs.subAccountDebtShares[_subAccount].getAmount(_debtPoolId),
      _debtPooInfo.totalValue,
      _debtPooInfo.totalShare
    );

    if (
      _debtAmount != 0 &&
      LibFullMath.mulDiv(
        _debtAmount * lyfDs.tokenConfigs[_debtPooInfo.token].to18ConversionFactor,
        getPriceUSD(_debtPooInfo.token, lyfDs),
        1e18
      ) <
      lyfDs.minDebtSize
    ) {
      revert LibLYF01_BorrowLessThanMinDebtSize();
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

    uint256 _pendingReward = lyfDs.pendingRewards[_lpToken];

    if (_pendingReward < _reinvestThreshold) {
      return;
    }

    uint256 _reinvestAmount;

    address _token0 = ISwapPairLike(_lpToken).token0();
    address _token1 = ISwapPairLike(_lpToken).token1();

    // calcualate reinvest bounty
    uint256 _reinvestBounty = (_pendingReward * _lpConfig.reinvestTreasuryBountyBps) / LibLYF01.MAX_BPS;

    {
      uint256 _actualPendingReward = _pendingReward - _reinvestBounty;

      // convert rewardToken to either token0 or token1
      if (_lpConfig.rewardToken == _token0 || _lpConfig.rewardToken == _token1) {
        _reinvestAmount = _actualPendingReward;
      } else {
        IERC20(_lpConfig.rewardToken).safeIncreaseAllowance(_lpConfig.router, _actualPendingReward);
        uint256[] memory _amounts = IRouterLike(_lpConfig.router).swapExactTokensForTokens(
          _actualPendingReward,
          0,
          _lpConfig.reinvestPath,
          address(this),
          block.timestamp
        );
        _reinvestAmount = _amounts[_amounts.length - 1];
      }
    }

    {
      // compose LP
      uint256 _token0Amount;
      uint256 _token1Amount;

      if (_lpConfig.reinvestPath[_lpConfig.reinvestPath.length - 1] == _token0) {
        _token0Amount = _reinvestAmount;
        IERC20(_token0).safeTransfer(_lpConfig.strategy, _reinvestAmount);
      } else {
        _token1Amount = _reinvestAmount;
        IERC20(_token1).safeTransfer(_lpConfig.strategy, _reinvestAmount);
      }

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
    }

    // transfer bounty to treasury
    IERC20(_lpConfig.rewardToken).safeTransfer(lyfDs.revenueTreasury, _reinvestBounty);

    // reset pending reward
    lyfDs.pendingRewards[_lpToken] = 0;

    emit LogReinvest(msg.sender, _pendingReward, _reinvestBounty);
  }

  function borrow(
    address _subAccount,
    address _token,
    address _lpToken,
    uint256 _amount,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal {
    if (_amount == 0) return;
    uint256 _debtPoolId = lyfDs.debtPoolIds[_token][_lpToken];
    if (_debtPoolId == 0) {
      revert LibLYF01_BadDebtPoolId();
    }

    LibUIntDoublyLinkedList.List storage userDebtShare = lyfDs.subAccountDebtShares[_subAccount];
    DebtPoolInfo storage debtPoolInfo = lyfDs.debtPoolInfos[_debtPoolId];

    userDebtShare.initIfNotExist();

    // use reserve if it is enough, else borrow from mm entirely
    if (lyfDs.reserves[_token] - lyfDs.protocolReserves[_token] >= _amount) {
      lyfDs.reserves[_token] -= _amount;
    } else {
      IMoneyMarket(lyfDs.moneyMarket).nonCollatBorrow(_token, _amount);
    }

    uint256 _shareToAdd = LibShareUtil.valueToShareRoundingUp(
      _amount,
      debtPoolInfo.totalShare,
      debtPoolInfo.totalValue
    );

    // update over collat debt
    debtPoolInfo.totalShare += _shareToAdd;
    debtPoolInfo.totalValue += _amount;

    // update user's debtshare
    userDebtShare.addOrUpdate(_debtPoolId, userDebtShare.getAmount(_debtPoolId) + _shareToAdd);

    if (userDebtShare.length() > lyfDs.maxNumOfDebtPerSubAccount) {
      revert LibLYF01_NumberOfTokenExceedLimit();
    }
  }

  function removeDebt(
    address _subAccount,
    uint256 _debtPoolId,
    uint256 _debtShareToRemove,
    uint256 _debtAmountToRemove,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal {
    uint256 _currentDebtShare = lyfDs.subAccountDebtShares[_subAccount].getAmount(_debtPoolId);

    // update user debtShare
    lyfDs.subAccountDebtShares[_subAccount].updateOrRemove(_debtPoolId, _currentDebtShare - _debtShareToRemove);

    DebtPoolInfo storage debtPoolInfo = lyfDs.debtPoolInfos[_debtPoolId];
    debtPoolInfo.totalShare -= _debtShareToRemove;
    debtPoolInfo.totalValue -= _debtAmountToRemove;
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
      revert LibLYF01_FeeOnTransferTokensNotSupported();
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
}
