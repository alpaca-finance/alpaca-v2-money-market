// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// libraries
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";

// interfaces
import { ILiquidationFacet } from "../interfaces/ILiquidationFacet.sol";
import { ILiquidationStrategy } from "../interfaces/ILiquidationStrategy.sol";
import { ILendFacet } from "../interfaces/ILendFacet.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

contract LiquidationFacet is ILiquidationFacet {
  using LibDoublyLinkedList for LibDoublyLinkedList.List;
  using LibSafeToken for IERC20;

  struct InternalLiquidationCallParams {
    address liquidationStrat;
    address subAccount;
    address repayToken;
    address collatToken;
    uint256 repayAmount;
    uint256 usedBorrowingPower;
    bytes paramsForStrategy;
  }

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  struct RepurchaseLocalVars {
    address subAccount;
    uint256 usedBorrowingPower;
    uint256 repayAmountWithFee;
    uint256 repurchaseFeeToProtocol;
    uint256 repayAmountWihtoutFee;
    uint256 repayTokenPrice;
  }

  function repurchase(
    address _account,
    uint256 _subAccountId,
    address _repayToken,
    address _collatToken,
    uint256 _desiredRepayAmount
  ) external nonReentrant returns (uint256 _collatAmountOut) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    if (!moneyMarketDs.repurchasersOk[msg.sender]) {
      revert LiquidationFacet_Unauthorized();
    }

    RepurchaseLocalVars memory vars;

    vars.subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    LibMoneyMarket01.accrueBorrowedPositionsOf(vars.subAccount, moneyMarketDs);

    // revert if position is healthy
    (vars.usedBorrowingPower, ) = LibMoneyMarket01.getTotalUsedBorrowingPower(vars.subAccount, moneyMarketDs);
    if (LibMoneyMarket01.getTotalBorrowingPower(vars.subAccount, moneyMarketDs) > vars.usedBorrowingPower) {
      revert LiquidationFacet_Healthy();
    }

    // cap repurchase amount if needed and calculate fee
    {
      // _maxAmountRepurchaseable = current debt + fee
      (, uint256 _currentDebtAmount) = LibMoneyMarket01.getOverCollatDebt(vars.subAccount, _repayToken, moneyMarketDs);
      uint256 _maxAmountRepurchaseable = (_currentDebtAmount *
        (moneyMarketDs.repurchaseFeeBps + LibMoneyMarket01.MAX_BPS)) / LibMoneyMarket01.MAX_BPS;

      // repay amount is capped if try to repay more than outstanding debt + fee
      if (_desiredRepayAmount > _maxAmountRepurchaseable) {
        // repayAmountWithFee = _currentDebtAmount + fee
        vars.repayAmountWithFee = _maxAmountRepurchaseable;
        // repayAmountWihtoutFee = _currentDebtAmount = repayAmountWithFee * _currentDebtAmount / _maxAmountRepurchaseable
        // calculate like this so we can close entire debt without dust
        vars.repayAmountWihtoutFee = (vars.repayAmountWithFee * _currentDebtAmount) / _maxAmountRepurchaseable;
      } else {
        vars.repayAmountWithFee = _desiredRepayAmount;
        vars.repayAmountWihtoutFee =
          (_desiredRepayAmount * (LibMoneyMarket01.MAX_BPS - moneyMarketDs.repurchaseFeeBps)) /
          LibMoneyMarket01.MAX_BPS;
      }

      vars.repurchaseFeeToProtocol = vars.repayAmountWithFee - vars.repayAmountWihtoutFee;
    }

    (vars.repayTokenPrice, ) = LibMoneyMarket01.getPriceUSD(_repayToken, moneyMarketDs);

    // revert if repay > x% of totalUsedBorrowingPower
    {
      uint256 _repaidBorrowingPower = LibMoneyMarket01.usedBorrowingPower(
        vars.repayAmountWihtoutFee,
        vars.repayTokenPrice,
        moneyMarketDs.tokenConfigs[_repayToken].borrowingFactor
      );
      if (_repaidBorrowingPower > (vars.usedBorrowingPower * moneyMarketDs.maxLiquidateBps) / LibMoneyMarket01.MAX_BPS)
        revert LiquidationFacet_RepayAmountExceedThreshold();
    }

    // calculate payout (collateral + reward)
    {
      (uint256 _collatTokenPrice, ) = LibMoneyMarket01.getPriceUSD(_collatToken, moneyMarketDs);

      uint256 _repayTokenPriceWithPremium = (vars.repayTokenPrice *
        (LibMoneyMarket01.MAX_BPS + moneyMarketDs.repurchaseRewardBps)) / LibMoneyMarket01.MAX_BPS;

      _collatAmountOut =
        (vars.repayAmountWithFee *
          _repayTokenPriceWithPremium *
          moneyMarketDs.tokenConfigs[_collatToken].to18ConversionFactor) /
        (_collatTokenPrice * moneyMarketDs.tokenConfigs[_collatToken].to18ConversionFactor);

      // revert if subAccount collat is not enough to cover desired repay amount
      // this could happen when there are multiple small collat and one large debt
      if (_collatAmountOut > moneyMarketDs.subAccountCollats[vars.subAccount].getAmount(_collatToken)) {
        revert LiquidationFacet_InsufficientAmount();
      }
    }

    // transfer tokens
    uint256 _repayTokenBefore = IERC20(_repayToken).balanceOf(address(this));
    IERC20(_repayToken).safeTransferFrom(msg.sender, address(this), vars.repayAmountWithFee);
    uint256 _actualRepayAmountWithoutFee = IERC20(_repayToken).balanceOf(address(this)) -
      _repayTokenBefore -
      vars.repurchaseFeeToProtocol;
    IERC20(_collatToken).safeTransfer(msg.sender, _collatAmountOut);
    IERC20(_repayToken).safeTransfer(moneyMarketDs.treasury, vars.repurchaseFeeToProtocol);

    // update states
    _reduceDebt(vars.subAccount, _repayToken, _actualRepayAmountWithoutFee, moneyMarketDs);
    _reduceCollateral(vars.subAccount, _collatToken, _collatAmountOut, moneyMarketDs);

    moneyMarketDs.reserves[_repayToken] += _actualRepayAmountWithoutFee;

    emit LogRepurchase(
      msg.sender,
      _repayToken,
      _collatToken,
      _actualRepayAmountWithoutFee,
      _collatAmountOut,
      vars.repurchaseFeeToProtocol,
      (_collatAmountOut * moneyMarketDs.repurchaseRewardBps) / LibMoneyMarket01.MAX_BPS
    );
  }

  function liquidationCall(
    address _liquidationStrat,
    address _account,
    uint256 _subAccountId,
    address _repayToken,
    address _collatToken,
    uint256 _repayAmount,
    bytes calldata _paramsForStrategy
  ) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    if (!moneyMarketDs.liquidationStratOk[_liquidationStrat] || !moneyMarketDs.liquidatorsOk[msg.sender]) {
      revert LiquidationFacet_Unauthorized();
    }

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    LibMoneyMarket01.accrueBorrowedPositionsOf(_subAccount, moneyMarketDs);

    // 1. check if position is underwater and can be liquidated
    uint256 _borrowingPower = LibMoneyMarket01.getTotalBorrowingPower(_subAccount, moneyMarketDs);
    (uint256 _usedBorrowingPower, ) = LibMoneyMarket01.getTotalUsedBorrowingPower(_subAccount, moneyMarketDs);
    if ((_borrowingPower * LibMoneyMarket01.MAX_BPS) > _usedBorrowingPower * moneyMarketDs.liquidationThresholdBps) {
      revert LiquidationFacet_Healthy();
    }

    InternalLiquidationCallParams memory _params = InternalLiquidationCallParams({
      liquidationStrat: _liquidationStrat,
      subAccount: _subAccount,
      repayToken: _repayToken,
      collatToken: _collatToken,
      repayAmount: _repayAmount,
      usedBorrowingPower: _usedBorrowingPower,
      paramsForStrategy: _paramsForStrategy
    });

    address _collatUnderlyingToken = moneyMarketDs.ibTokenToTokens[_collatToken];
    // handle liqudiate ib as collat
    if (_collatUnderlyingToken != address(0)) {
      _ibLiquidationCall(_params, _collatUnderlyingToken, moneyMarketDs);
    } else {
      _liquidationCall(_params, moneyMarketDs);
    }
  }

  function _liquidationCall(
    InternalLiquidationCallParams memory params,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    // 2. send all collats under subaccount to strategy
    uint256 _collatAmountBefore = IERC20(params.collatToken).balanceOf(address(this));
    uint256 _repayAmountBefore = IERC20(params.repayToken).balanceOf(address(this));

    IERC20(params.collatToken).safeTransfer(
      params.liquidationStrat,
      moneyMarketDs.subAccountCollats[params.subAccount].getAmount(params.collatToken)
    );

    // 3. call executeLiquidation on strategy
    uint256 _actualRepayAmount = _getActualRepayAmount(
      params.subAccount,
      params.repayToken,
      params.repayAmount,
      moneyMarketDs
    );
    uint256 _feeToTreasury = (_actualRepayAmount * moneyMarketDs.liquidationFeeBps) / 10000;

    ILiquidationStrategy(params.liquidationStrat).executeLiquidation(
      params.collatToken,
      params.repayToken,
      _actualRepayAmount + _feeToTreasury,
      address(this),
      params.paramsForStrategy
    );

    // 4. check repaid amount, take fees, and update states
    uint256 _repaidAmount;
    {
      uint256 _repayAmountFromLiquidation = IERC20(params.repayToken).balanceOf(address(this)) - _repayAmountBefore;
      _repaidAmount = _repayAmountFromLiquidation - _feeToTreasury;
      (uint256 _repayTokenPrice, ) = LibMoneyMarket01.getPriceUSD(params.repayToken, moneyMarketDs);
      uint256 _repaidBorrowingPower = LibMoneyMarket01.usedBorrowingPower(
        _repaidAmount,
        _repayTokenPrice,
        moneyMarketDs.tokenConfigs[params.repayToken].borrowingFactor
      );
      // revert if repay > x% of totalUsedBorrowingPower
      if (
        _repaidBorrowingPower > (moneyMarketDs.maxLiquidateBps * params.usedBorrowingPower) / LibMoneyMarket01.MAX_BPS
      ) revert LiquidationFacet_RepayAmountExceedThreshold();
    }

    uint256 _collatSold = _collatAmountBefore - IERC20(params.collatToken).balanceOf(address(this));

    moneyMarketDs.reserves[params.repayToken] += _repaidAmount;
    IERC20(params.repayToken).safeTransfer(moneyMarketDs.treasury, _feeToTreasury);

    // give priority to fee
    _reduceDebt(params.subAccount, params.repayToken, _repaidAmount, moneyMarketDs);
    _reduceCollateral(params.subAccount, params.collatToken, _collatSold, moneyMarketDs);

    emit LogLiquidate(
      msg.sender,
      params.liquidationStrat,
      params.repayToken,
      params.collatToken,
      _repaidAmount,
      _collatSold,
      _feeToTreasury
    );
  }

  struct InternalIbLiquidationCallLocalVars {
    uint256 underlyingAmountBefore;
    uint256 repayAmountBefore;
    uint256 totalToken;
    uint256 ibTotalSupply;
    uint256 actualRepayAmount;
    uint256 feeToTreasury;
    uint256 repaidAmount;
    uint256 underlyingSold;
    uint256 collatSold;
  }

  function _ibLiquidationCall(
    InternalLiquidationCallParams memory params,
    address _collatUnderlyingToken,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    InternalIbLiquidationCallLocalVars memory vars;

    // 2. convert collat amount under subaccount to underlying amount and send underlying to strategy
    vars.underlyingAmountBefore = IERC20(_collatUnderlyingToken).balanceOf(address(this));
    vars.repayAmountBefore = IERC20(params.repayToken).balanceOf(address(this));
    vars.totalToken = LibMoneyMarket01.getTotalToken(_collatUnderlyingToken, moneyMarketDs);
    vars.ibTotalSupply = IERC20(params.collatToken).totalSupply();

    // if mm has no actual token left, withdraw will fail anyway
    IERC20(_collatUnderlyingToken).safeTransfer(
      params.liquidationStrat,
      LibShareUtil.shareToValue(
        moneyMarketDs.subAccountCollats[params.subAccount].getAmount(params.collatToken),
        vars.totalToken,
        vars.ibTotalSupply
      )
    );

    // 3. call executeLiquidation on strategy to liquidate underlying token
    vars.actualRepayAmount = _getActualRepayAmount(
      params.subAccount,
      params.repayToken,
      params.repayAmount,
      moneyMarketDs
    );
    vars.feeToTreasury = (vars.actualRepayAmount * moneyMarketDs.liquidationFeeBps) / 10000;

    ILiquidationStrategy(params.liquidationStrat).executeLiquidation(
      _collatUnderlyingToken,
      params.repayToken,
      vars.actualRepayAmount + vars.feeToTreasury,
      address(this),
      params.paramsForStrategy
    );

    // 4. check repaid amount, take fees, and update states
    {
      uint256 _repayAmountFromLiquidation = IERC20(params.repayToken).balanceOf(address(this)) - vars.repayAmountBefore;
      vars.repaidAmount = _repayAmountFromLiquidation - vars.feeToTreasury;
      (uint256 _repayTokenPrice, ) = LibMoneyMarket01.getPriceUSD(params.repayToken, moneyMarketDs);
      uint256 _repaidBorrowingPower = LibMoneyMarket01.usedBorrowingPower(
        vars.repaidAmount,
        _repayTokenPrice,
        moneyMarketDs.tokenConfigs[params.repayToken].borrowingFactor
      );
      // revert if repay > x% of totalUsedBorrowingPower
      if (
        _repaidBorrowingPower > (moneyMarketDs.maxLiquidateBps * params.usedBorrowingPower) / LibMoneyMarket01.MAX_BPS
      ) revert LiquidationFacet_RepayAmountExceedThreshold();
    }

    vars.underlyingSold = vars.underlyingAmountBefore - IERC20(_collatUnderlyingToken).balanceOf(address(this));

    // cached ibTotalSupply, totalToken can be used here (after liquidation) because we haven't withdraw ib yet
    vars.collatSold = LibShareUtil.valueToShare(vars.underlyingSold, vars.ibTotalSupply, vars.totalToken);

    IERC20(params.repayToken).safeTransfer(moneyMarketDs.treasury, vars.feeToTreasury);

    LibMoneyMarket01.withdraw(params.collatToken, vars.collatSold, address(this), moneyMarketDs);

    // give priority to fee
    _reduceDebt(params.subAccount, params.repayToken, vars.repaidAmount, moneyMarketDs);
    _reduceCollateral(params.subAccount, params.collatToken, vars.collatSold, moneyMarketDs);

    emit LogLiquidateIb(
      msg.sender,
      params.liquidationStrat,
      params.repayToken,
      params.collatToken,
      vars.repaidAmount,
      vars.collatSold,
      vars.underlyingSold,
      vars.feeToTreasury
    );
  }

  /// @dev min(repayAmount, debtValue)
  function _getActualRepayAmount(
    address _subAccount,
    address _repayToken,
    uint256 _repayAmount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _actualRepayAmount) {
    uint256 _debtShare = moneyMarketDs.subAccountDebtShares[_subAccount].getAmount(_repayToken);
    // for ib debtValue is in ib shares not in underlying
    uint256 _debtValue = LibShareUtil.shareToValue(
      _debtShare,
      moneyMarketDs.overCollatDebtValues[_repayToken],
      moneyMarketDs.overCollatDebtShares[_repayToken]
    );

    _actualRepayAmount = _repayAmount > _debtValue ? _debtValue : _repayAmount;
  }

  function _reduceDebt(
    address _subAccount,
    address _repayToken,
    uint256 _repayAmount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    uint256 _debtShare = moneyMarketDs.subAccountDebtShares[_subAccount].getAmount(_repayToken);
    uint256 _repayShare = LibShareUtil.valueToShare(
      _repayAmount,
      moneyMarketDs.overCollatDebtShares[_repayToken],
      moneyMarketDs.overCollatDebtValues[_repayToken]
    );
    moneyMarketDs.subAccountDebtShares[_subAccount].updateOrRemove(_repayToken, _debtShare - _repayShare);
    moneyMarketDs.overCollatDebtShares[_repayToken] -= _repayShare;
    moneyMarketDs.overCollatDebtValues[_repayToken] -= _repayAmount;
  }

  function _reduceCollateral(
    address _subAccount,
    address _collatToken,
    uint256 _amountOut,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    uint256 _collatTokenAmount = moneyMarketDs.subAccountCollats[_subAccount].getAmount(_collatToken);
    moneyMarketDs.subAccountCollats[_subAccount].updateOrRemove(_collatToken, _collatTokenAmount - _amountOut);
    moneyMarketDs.collats[_collatToken] -= _amountOut;
  }
}
