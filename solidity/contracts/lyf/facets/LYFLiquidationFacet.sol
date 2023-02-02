// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// libraries
import { LibLYF01 } from "../libraries/LibLYF01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibUIntDoublyLinkedList } from "../libraries/LibUIntDoublyLinkedList.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";

// interfaces
import { ILYFLiquidationFacet } from "../interfaces/ILYFLiquidationFacet.sol";
import { ILiquidationStrategy } from "../interfaces/ILiquidationStrategy.sol";
import { IMoneyMarket } from "../interfaces/IMoneyMarket.sol";
import { ISwapPairLike } from "../interfaces/ISwapPairLike.sol";
import { IMasterChefLike } from "../interfaces/IMasterChefLike.sol";
import { IStrat } from "../interfaces/IStrat.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

import { console } from "solidity/tests/utils/console.sol";

contract LYFLiquidationFacet is ILYFLiquidationFacet {
  using LibSafeToken for IERC20;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;
  using LibUIntDoublyLinkedList for LibUIntDoublyLinkedList.List;

  // todo: move to state
  uint256 constant REPURCHASE_FEE_BPS = 100;
  uint256 constant REPURCHASE_REWARD_BPS = 100;
  uint256 constant LIQUIDATION_FEE_BPS = 100;
  uint256 constant MAX_LIQUIDATE_BPS = 5000;
  uint256 constant liquidationRewardBps = 5000;

  event LogRepurchase(
    address indexed repurchaser,
    address _repayToken,
    address _collatToken,
    uint256 _amountIn,
    uint256 _amountOut,
    uint256 _fee
  );

  event LogLiquidate(
    address indexed liquidator,
    address _strat,
    address _repayToken,
    address _collatToken,
    uint256 _amountIn,
    uint256 _amountOut,
    uint256 _feeToTreasury,
    uint256 _feeToLiquidator
  );

  event LogLiquidateLP(
    address indexed liquidator,
    address _account,
    uint256 _subAccountId,
    address _lpToken,
    uint256 _lpSharesToLiquidate,
    uint256 _amount0Repaid,
    uint256 _amount1Repaid,
    uint256 _remainingAmount0AfterRepay,
    uint256 _remainingAmount1AfterRepay
  );

  struct InternalLiquidationCallParams {
    address liquidationStrat;
    address subAccount;
    address repayToken;
    address collatToken;
    uint256 repayAmount;
    uint256 usedBorrowingPower;
    uint256 debtShareId;
    uint256 minReceive;
    uint256 collatAmountBefore;
    uint256 repayAmountBefore;
    uint256 subAccountCollatAmount;
  }

  struct LiquidateLPLocalVars {
    address subAccount;
    address token0;
    address token1;
    uint256 debtPoolId0;
    uint256 debtPoolId1;
    uint256 token0Return;
    uint256 token1Return;
    uint256 actualAmount0ToRepay;
    uint256 actualAmount1ToRepay;
    uint256 remainingAmount0AfterRepay;
    uint256 remainingAmount1AfterRepay;
  }

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  function repurchase(
    address _account,
    uint256 _subAccountId,
    address _debtToken,
    address _collatToken,
    address _lpToken,
    uint256 _desiredRepayAmountWithFee,
    uint256 _minCollatOut
  ) external nonReentrant returns (uint256 _collatAmountOut) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);
    uint256 _debtPoolId = lyfDs.debtPoolIds[_debtToken][_lpToken];

    // accrue interest for all debt tokens which are under subaccount
    LibLYF01.accrueDebtSharesOf(_subAccount, lyfDs);

    // health check sub account borrowing power
    uint256 _usedBorrowingPower = LibLYF01.getTotalUsedBorrowingPower(_subAccount, lyfDs);
    {
      uint256 _totalBorrowingPower = LibLYF01.getTotalBorrowingPower(_subAccount, lyfDs);
      if (_totalBorrowingPower > _usedBorrowingPower) {
        revert LYFLiquidationFacet_Healthy();
      }
    }

    // get max repay amount possible could repay
    (uint256 _actualRepayAmountWithFee, uint256 _actualFee) = _getActualRepayAmountWithFee(
      _subAccount,
      _debtPoolId,
      _desiredRepayAmountWithFee,
      lyfDs
    );

    {
      // check how much borrowing power reduced after repay (without fee)
      LibLYF01.TokenConfig memory _debtTokenConfig = lyfDs.tokenConfigs[_debtToken];
      uint256 _repayTokenPrice = LibLYF01.getPriceUSD(_debtToken, lyfDs);
      uint256 _repaidBorrowingPower = LibLYF01.usedBorrowingPower(
        _actualRepayAmountWithFee - _actualFee,
        _repayTokenPrice,
        _debtTokenConfig.borrowingFactor,
        _debtTokenConfig.to18ConversionFactor
      );

      if (_repaidBorrowingPower * LibLYF01.MAX_BPS > _usedBorrowingPower * MAX_LIQUIDATE_BPS) {
        revert LYFLiquidationFacet_RepayDebtValueTooHigh();
      }

      _collatAmountOut = _calculateCollatForRepurchaser(
        _subAccount,
        _collatToken,
        (_actualRepayAmountWithFee * _repayTokenPrice * _debtTokenConfig.to18ConversionFactor) / 1e18, // repaid with fee in USD
        _minCollatOut,
        lyfDs
      );
    }

    // transfer tokens
    // in case of fee on transfer tokens, debt would be repaid by amount after transfer fee
    // which won't be able to repurchase entire position
    {
      uint256 _actualReceivedRepayAmountWithoutFee = LibLYF01.unsafePullTokens(
        _debtToken,
        msg.sender,
        _actualRepayAmountWithFee
      ) - _actualFee;

      // update debt, collateral for sub account
      if (_actualReceivedRepayAmountWithoutFee > 0) {
        _removeDebtByAmount(_subAccount, _debtPoolId, _actualReceivedRepayAmountWithoutFee, lyfDs);
      }
      LibLYF01.removeCollateral(_subAccount, _collatToken, _collatAmountOut, lyfDs);

      // transfer tokens out
      IERC20(_debtToken).safeTransfer(lyfDs.liquidationTreasury, _actualFee);
      IERC20(_collatToken).safeTransfer(msg.sender, _collatAmountOut);

      emit LogRepurchase(
        msg.sender,
        _debtToken,
        _collatToken,
        _actualReceivedRepayAmountWithoutFee,
        _collatAmountOut,
        _actualFee
      );
    }
  }

  function liquidationCall(
    address _liquidationStrat,
    address _account,
    uint256 _subAccountId,
    address _repayToken,
    address _collatToken,
    address _lpToken,
    uint256 _repayAmount,
    uint256 _minReceive
  ) external nonReentrant {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    if (!lyfDs.liquidationStratOk[_liquidationStrat] || !lyfDs.liquidationCallersOk[msg.sender]) {
      revert LYFLiquidationFacet_Unauthorized();
    }

    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);
    uint256 _debtPoolId = lyfDs.debtPoolIds[_repayToken][_lpToken];

    LibLYF01.accrueDebtSharesOf(_subAccount, lyfDs);

    // 1. check if position is underwater and can be liquidated
    // todo: threshold
    uint256 _totalBorrowingPower = LibLYF01.getTotalBorrowingPower(_subAccount, lyfDs);
    uint256 _usedBorrowingPower = LibLYF01.getTotalUsedBorrowingPower(_subAccount, lyfDs);
    if (_totalBorrowingPower * LibLYF01.MAX_BPS > _usedBorrowingPower * 9000) {
      revert LYFLiquidationFacet_Healthy();
    }

    InternalLiquidationCallParams memory _params = InternalLiquidationCallParams({
      liquidationStrat: _liquidationStrat,
      subAccount: _subAccount,
      repayToken: _repayToken,
      collatToken: _collatToken,
      repayAmount: _repayAmount,
      usedBorrowingPower: _usedBorrowingPower,
      debtShareId: _debtPoolId,
      minReceive: _minReceive,
      collatAmountBefore: IERC20(_collatToken).balanceOf(address(this)),
      repayAmountBefore: IERC20(_repayToken).balanceOf(address(this)),
      subAccountCollatAmount: lyfDs.subAccountCollats[_subAccount].getAmount(_collatToken)
    });

    _liquidationCall(_params, lyfDs);
  }

  function _liquidationCall(InternalLiquidationCallParams memory _params, LibLYF01.LYFDiamondStorage storage lyfDs)
    internal
  {
    // 2. send all collats under subaccount to strategy
    IERC20(_params.collatToken).safeTransfer(_params.liquidationStrat, _params.subAccountCollatAmount);

    // 3. call executeLiquidation on strategy
    uint256 _maxPossibleRepayAmount = _getActualRepayAmount(
      _params.subAccount,
      _params.debtShareId,
      _params.repayAmount,
      lyfDs
    );
    uint256 _maxPossibleFee = (_maxPossibleRepayAmount * LIQUIDATION_FEE_BPS) / LibLYF01.MAX_BPS;

    console.log("[C] Before ILiquidationStrategy:_maxPossibleRepayAmount", _maxPossibleRepayAmount);

    uint256 _expectedMaxRepayAmountWithFee = _maxPossibleRepayAmount + _maxPossibleFee;

    console.log("[C] Before ILiquidationStrategy:executeLiquidation");
    ILiquidationStrategy(_params.liquidationStrat).executeLiquidation(
      _params.collatToken,
      _params.repayToken,
      _params.subAccountCollatAmount,
      _expectedMaxRepayAmountWithFee,
      _params.minReceive
    );
    console.log("[C] After ILiquidationStrategy:executeLiquidation");

    // 4. check repaid amount, take fees, and update states
    (uint256 _repaidAmount, uint256 _actualLiquidationFee) = _calculateActualRepayAmountAndFee(
      _params,
      _params.repayAmountBefore,
      _expectedMaxRepayAmountWithFee,
      _maxPossibleFee
    );

    // 5. split fee between liquidator and treasury
    uint256 _feeToLiquidator = (_actualLiquidationFee * liquidationRewardBps) / LibLYF01.MAX_BPS;
    uint256 _feeToTreasury = _actualLiquidationFee - _feeToLiquidator;

    _validateBorrowingPower(_params.repayToken, _repaidAmount, _params.usedBorrowingPower, lyfDs);

    uint256 _collatSold = _params.collatAmountBefore - IERC20(_params.collatToken).balanceOf(address(this));

    console.log("[C]:_liquidationCall:_collatSold", _collatSold);
    console.log("[C]:_liquidationCall:_repaidAmount", _repaidAmount);
    lyfDs.reserves[_params.repayToken] += _repaidAmount;

    IERC20(_params.repayToken).safeTransfer(msg.sender, _feeToLiquidator);
    IERC20(_params.repayToken).safeTransfer(lyfDs.liquidationTreasury, _feeToTreasury);

    // give priority to fee
    if (_repaidAmount > 0) {
      _removeDebtByAmount(_params.subAccount, _params.debtShareId, _repaidAmount, lyfDs);
    }
    LibLYF01.removeCollateral(_params.subAccount, _params.collatToken, _collatSold, lyfDs);

    emit LogLiquidate(
      msg.sender,
      _params.liquidationStrat,
      _params.repayToken,
      _params.collatToken,
      _repaidAmount,
      _collatSold,
      _feeToTreasury,
      _feeToLiquidator
    );
  }

  function lpLiquidationCall(
    address _account,
    uint256 _subAccountId,
    address _lpToken,
    uint256 _lpSharesToLiquidate,
    uint256 _amount0ToRepay,
    uint256 _amount1ToRepay
  ) external {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    if (!lyfDs.liquidationCallersOk[msg.sender]) {
      revert LYFLiquidationFacet_Unauthorized();
    }

    if (lyfDs.tokenConfigs[_lpToken].tier != LibLYF01.AssetTier.LP) {
      revert LYFLiquidationFacet_InvalidAssetTier();
    }

    LibLYF01.LPConfig memory lpConfig = lyfDs.lpConfigs[_lpToken];

    LiquidateLPLocalVars memory vars;

    vars.subAccount = LibLYF01.getSubAccount(_account, _subAccountId);

    vars.token0 = ISwapPairLike(_lpToken).token0();
    vars.token1 = ISwapPairLike(_lpToken).token1();

    vars.debtPoolId0 = lyfDs.debtPoolIds[vars.token0][_lpToken];
    vars.debtPoolId1 = lyfDs.debtPoolIds[vars.token1][_lpToken];

    LibLYF01.accrueDebtSharesOf(vars.subAccount, lyfDs);

    // 0. check borrowing power
    // todo: threshold
    uint256 _totalBorrowingPower = LibLYF01.getTotalBorrowingPower(vars.subAccount, lyfDs);
    uint256 _usedBorrowingPower = LibLYF01.getTotalUsedBorrowingPower(vars.subAccount, lyfDs);
    if (_totalBorrowingPower * LibLYF01.MAX_BPS > _usedBorrowingPower * 9000) {
      revert LYFLiquidationFacet_Healthy();
    }

    // 1. remove LP collat
    uint256 _lpFromCollatRemoval = LibLYF01.removeCollateral(vars.subAccount, _lpToken, _lpSharesToLiquidate, lyfDs);

    // 2. remove from masterchef staking
    IMasterChefLike(lpConfig.masterChef).withdraw(lpConfig.poolId, _lpFromCollatRemoval);

    IERC20(_lpToken).safeTransfer(lpConfig.strategy, _lpFromCollatRemoval);

    (vars.token0Return, vars.token1Return) = IStrat(lpConfig.strategy).removeLiquidity(_lpToken);

    // 3. repay what we can and add remaining to collat
    (vars.actualAmount0ToRepay, vars.remainingAmount0AfterRepay) = _repayAndAddRemainingToCollat(
      vars.subAccount,
      vars.debtPoolId0,
      vars.token0,
      _amount0ToRepay,
      vars.token0Return,
      lyfDs
    );
    (vars.actualAmount1ToRepay, vars.remainingAmount1AfterRepay) = _repayAndAddRemainingToCollat(
      vars.subAccount,
      vars.debtPoolId1,
      vars.token1,
      _amount1ToRepay,
      vars.token1Return,
      lyfDs
    );

    emit LogLiquidateLP(
      msg.sender,
      _account,
      _subAccountId,
      _lpToken,
      _lpSharesToLiquidate,
      vars.actualAmount0ToRepay,
      vars.actualAmount1ToRepay,
      vars.remainingAmount0AfterRepay,
      vars.remainingAmount1AfterRepay
    );
  }

  function _repayAndAddRemainingToCollat(
    address _subAccount,
    uint256 _debtPoolId,
    address _token,
    uint256 _amountToRepay,
    uint256 _amountAvailable,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal returns (uint256 _actualAmountToRepay, uint256 _remainingAmountAfterRepay) {
    // repay what we can
    _actualAmountToRepay = _getActualRepayAmount(_subAccount, _debtPoolId, _amountToRepay, lyfDs);
    _actualAmountToRepay = _actualAmountToRepay > _amountAvailable ? _amountAvailable : _actualAmountToRepay;

    if (_actualAmountToRepay > 0) {
      uint256 _feeToTreasury = (_actualAmountToRepay * LIQUIDATION_FEE_BPS) / 10000;
      _removeDebtByAmount(_subAccount, _debtPoolId, _actualAmountToRepay - _feeToTreasury, lyfDs);
      // transfer fee to treasury
      IERC20(_token).safeTransfer(lyfDs.liquidationTreasury, _feeToTreasury);
    }

    // add remaining as subAccount collateral
    _remainingAmountAfterRepay = _amountAvailable - _actualAmountToRepay;
    if (_remainingAmountAfterRepay > 0) {
      LibLYF01.addCollatWithoutMaxCollatNumCheck(_subAccount, _token, _remainingAmountAfterRepay, lyfDs);
    }
  }

  /// @dev min(amountToRepurchase, debtValue)
  function _getActualRepayAmount(
    address _subAccount,
    uint256 _debtPoolId,
    uint256 _repayAmount,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal view returns (uint256 _actualToRepay) {
    LibLYF01.DebtPoolInfo storage debtPoolInfo = lyfDs.debtPoolInfos[_debtPoolId];
    uint256 _debtShare = lyfDs.subAccountDebtShares[_subAccount].getAmount(_debtPoolId);
    // Note: precision loss 1 wei when convert share back to value
    uint256 _debtValue = LibShareUtil.shareToValue(_debtShare, debtPoolInfo.totalValue, debtPoolInfo.totalShare);

    _actualToRepay = _repayAmount > _debtValue ? _debtValue : _repayAmount;
  }

  function _calculateCollatForRepurchaser(
    address _subAccount,
    address _collatToken,
    uint256 _repaidAmountWithFeeUSD,
    uint256 _minReceive,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal view returns (uint256 _collatAmountOut) {
    IMoneyMarket _moneyMarket = lyfDs.moneyMarket;
    address _underlyingToken = _moneyMarket.getTokenFromIbToken(_collatToken);

    uint256 _collatTokenPrice;
    if (_underlyingToken != address(0)) {
      // if _collatToken is ibToken convert underlying price to ib price
      _collatTokenPrice =
        (LibLYF01.getPriceUSD(_underlyingToken, lyfDs) *
          LibLYF01.getIbToUnderlyingConversionFactor(_collatToken, _underlyingToken, _moneyMarket)) /
        1e18;
    } else {
      // _collatToken is normal ERC20 or LP token
      _collatTokenPrice = LibLYF01.getPriceUSD(_collatToken, lyfDs);
    }
    uint256 _exectReceiveUSD = (_repaidAmountWithFeeUSD * (REPURCHASE_REWARD_BPS + LibLYF01.MAX_BPS)) /
      LibLYF01.MAX_BPS;

    // _collatAmountOut = _collatValueInUSD + _rewardInUSD
    _collatAmountOut =
      (_exectReceiveUSD * 1e18) /
      (_collatTokenPrice * lyfDs.tokenConfigs[_collatToken].to18ConversionFactor);

    uint256 _totalSubAccountCollat = lyfDs.subAccountCollats[_subAccount].getAmount(_collatToken);

    if (_collatAmountOut > _totalSubAccountCollat) {
      revert LYFLiquidationFacet_InsufficientAmount();
    }

    if (_collatAmountOut < _minReceive) {
      revert LYFLiquidationFacet_TooLittleReceived();
    }
  }

  function _removeDebtByAmount(
    address _subAccount,
    uint256 _debtPoolId,
    uint256 _repayAmount,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal {
    LibLYF01.DebtPoolInfo storage debtPoolInfo = lyfDs.debtPoolInfos[_debtPoolId];
    uint256 _shareToRepay = LibShareUtil.valueToShare(_repayAmount, debtPoolInfo.totalShare, debtPoolInfo.totalValue);

    LibLYF01.removeDebt(_subAccount, _debtPoolId, _shareToRepay, _repayAmount, lyfDs);
  }

  function _getActualRepayAmountWithFee(
    address _subAccount,
    uint256 _debtPoolId,
    uint256 _desiredRepayAmountWithFee,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal view returns (uint256 _actualRepayAmountWithFee, uint256 _actualFee) {
    LibLYF01.DebtPoolInfo storage debtPoolInfo = lyfDs.debtPoolInfos[_debtPoolId];
    uint256 _maxRepayShare = lyfDs.subAccountDebtShares[_subAccount].getAmount(_debtPoolId);
    uint256 _maxRepayAmount = LibShareUtil.shareToValue(
      _maxRepayShare,
      debtPoolInfo.totalValue,
      debtPoolInfo.totalShare
    );
    _actualFee = (_maxRepayAmount * REPURCHASE_FEE_BPS) / LibLYF01.MAX_BPS;
    // set actual as maximum possible to repay
    _actualRepayAmountWithFee = _maxRepayAmount + _actualFee;

    // if desired repay amount is less than maximum repay amount,
    // then re calculate actual repay amount and fee by desired amount
    if (_desiredRepayAmountWithFee < _actualRepayAmountWithFee) {
      _actualFee = (_actualFee * _desiredRepayAmountWithFee) / _actualRepayAmountWithFee;
      _actualRepayAmountWithFee = _desiredRepayAmountWithFee;
    }
  }

  function _validateBorrowingPower(
    address _repayToken,
    uint256 _repaidAmount,
    uint256 _usedBorrowingPower,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal view {
    uint256 _repayTokenPrice = LibLYF01.getPriceUSD(_repayToken, lyfDs);
    uint256 _repaidBorrowingPower = LibLYF01.usedBorrowingPower(
      _repaidAmount,
      _repayTokenPrice,
      lyfDs.tokenConfigs[_repayToken].borrowingFactor,
      lyfDs.tokenConfigs[_repayToken].to18ConversionFactor
    );
    console.log("[C]_validateBorrowingPower:_repaidBorrowingPower", _repaidBorrowingPower);
    console.log("[C]_validateBorrowingPower:_usedBorrowingPower", _usedBorrowingPower);
    if (_repaidBorrowingPower * LibLYF01.MAX_BPS > (_usedBorrowingPower * MAX_LIQUIDATE_BPS)) {
      revert LYFLiquidationFacet_RepayAmountExceedThreshold();
    }
  }

  function _calculateActualRepayAmountAndFee(
    InternalLiquidationCallParams memory params,
    uint256 _repayAmountBefore,
    uint256 _expectedMaxRepayAmount,
    uint256 _maxFeePossible
  ) internal view returns (uint256 _actualRepayAmount, uint256 _actualLiquidationFee) {
    uint256 _amountFromLiquidationStrat = IERC20(params.repayToken).balanceOf(address(this)) - _repayAmountBefore;
    console.log("[C]:_calculateActualRepayAmountAndFee:_amountFromLiquidationStrat", _amountFromLiquidationStrat);
    console.log("[C]:_calculateActualRepayAmountAndFee:_maxFeePossible", _maxFeePossible);
    console.log("[C]:_calculateActualRepayAmountAndFee:_expectedMaxRepayAmount", _expectedMaxRepayAmount);
    _actualLiquidationFee = (_amountFromLiquidationStrat * _maxFeePossible) / _expectedMaxRepayAmount;
    _actualRepayAmount = _amountFromLiquidationStrat - _actualLiquidationFee;
  }
}
