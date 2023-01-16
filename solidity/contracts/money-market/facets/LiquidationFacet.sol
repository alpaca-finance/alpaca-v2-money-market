// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// ---- Libraries ---- //
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";

// ---- Interfaces ---- //
import { ILiquidationFacet } from "../interfaces/ILiquidationFacet.sol";
import { ILiquidationStrategy } from "../interfaces/ILiquidationStrategy.sol";
import { ILendFacet } from "../interfaces/ILendFacet.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

/// @title LiquidationFacet is dedicated to repurchasing and liquidating
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

  /// @notice Repurchase the debt token in exchange of a collateral token
  /// @param _account The account to be repurchased
  /// @param _subAccountId The index to derive the subaccount
  /// @param _repayToken The token that will be repurchase and repay the debt
  /// @param _collatToken The collateral token that will be used for exchange
  /// @param _desiredRepayAmount The amount of debt token that the repurchaser will provide
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
    if (LibMoneyMarket01.getTotalBorrowingPower(vars.subAccount, moneyMarketDs) >= vars.usedBorrowingPower) {
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

    vars.repayTokenPrice = LibMoneyMarket01.getPriceUSD(_repayToken, moneyMarketDs);

    // revert if repay > x% of totalUsedBorrowingPower
    _validateBorrowingPower(_repayToken, vars.repayAmountWihtoutFee, vars.usedBorrowingPower, moneyMarketDs);

    // calculate payout (collateral + reward)
    {
      uint256 _collatTokenPrice = LibMoneyMarket01.getPriceUSD(_collatToken, moneyMarketDs);

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

  /// @notice Liquidate the collateral token in exchange of the debt token
  /// @param _liquidationStrat The address of strategy used in liqudation
  /// @param _account The account to be repurchased
  /// @param _subAccountId The index to derive the subaccount
  /// @param _repayToken The token that will be repurchase and repay the debt
  /// @param _collatToken The collateral token that will be used for exchange
  /// @param _repayAmount The amount of debt token will be repaid after exchaing the collateral
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

    moneyMarketDs.liquidateExec = LibMoneyMarket01._ENTERED_LIQUIDATE;

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    LibMoneyMarket01.accrueBorrowedPositionsOf(_subAccount, moneyMarketDs);

    // 1. check if position is underwater and can be liquidated
    uint256 _borrowingPower = LibMoneyMarket01.getTotalBorrowingPower(_subAccount, moneyMarketDs);
    (uint256 _usedBorrowingPower, ) = LibMoneyMarket01.getTotalUsedBorrowingPower(_subAccount, moneyMarketDs);
    if ((_borrowingPower * LibMoneyMarket01.MAX_BPS) >= _usedBorrowingPower * moneyMarketDs.liquidationThresholdBps) {
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

    _liquidationCall(_params, moneyMarketDs);

    moneyMarketDs.liquidateExec = LibMoneyMarket01._NOT_ENTERED_LIQUIDATE;
  }

  function _liquidationCall(
    InternalLiquidationCallParams memory params,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    // 2. send all collats under subaccount to strategy
    uint256 _collatAmountBefore = IERC20(params.collatToken).balanceOf(address(this));
    uint256 _repayAmountBefore = IERC20(params.repayToken).balanceOf(address(this));
    uint256 _subAccountCollatAmount = moneyMarketDs.subAccountCollats[params.subAccount].getAmount(params.collatToken);

    IERC20(params.collatToken).safeTransfer(params.liquidationStrat, _subAccountCollatAmount);

    // 3. call executeLiquidation on strategy
    uint256 _maxPossibleRepayAmount = _calculateMaxPossibleRepayAmount(
      params.subAccount,
      params.repayToken,
      params.repayAmount,
      moneyMarketDs
    );
    uint256 _maxFeePossible = (_maxPossibleRepayAmount * moneyMarketDs.liquidationFeeBps) / 10000;

    uint256 _expectMaxRepayAmount = _maxPossibleRepayAmount + _maxFeePossible;

    ILiquidationStrategy(params.liquidationStrat).executeLiquidation(
      params.collatToken,
      params.repayToken,
      _subAccountCollatAmount,
      _expectMaxRepayAmount,
      params.paramsForStrategy
    );

    // 4. check repaid amount, take fees, and update states
    (uint256 _repaidAmount, uint256 _actualLiquidationFee) = _calculateActualRepayAmountAndFee(
      params,
      _repayAmountBefore,
      _expectMaxRepayAmount,
      _maxFeePossible
    );

    _validateBorrowingPower(params.repayToken, _repaidAmount, params.usedBorrowingPower, moneyMarketDs);

    uint256 _collatSold = _collatAmountBefore - IERC20(params.collatToken).balanceOf(address(this));

    moneyMarketDs.reserves[params.repayToken] += _repaidAmount;
    IERC20(params.repayToken).safeTransfer(moneyMarketDs.treasury, _actualLiquidationFee);

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
      _actualLiquidationFee
    );
  }

  /// @dev min(repayAmount, debtValue)
  function _calculateMaxPossibleRepayAmount(
    address _subAccount,
    address _repayToken,
    uint256 _repayAmount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _maxPossibleRepayAmount) {
    uint256 _debtShare = moneyMarketDs.subAccountDebtShares[_subAccount].getAmount(_repayToken);
    // for ib debtValue is in ib shares not in underlying
    uint256 _debtValue = LibShareUtil.shareToValue(
      _debtShare,
      moneyMarketDs.overCollatDebtValues[_repayToken],
      moneyMarketDs.overCollatDebtShares[_repayToken]
    );

    _maxPossibleRepayAmount = _repayAmount > _debtValue ? _debtValue : _repayAmount;
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

    moneyMarketDs.globalDebts[_repayToken] -= _repayAmount;
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

  function _validateBorrowingPower(
    address _repayToken,
    uint256 _repaidAmount,
    uint256 _usedBorrowingPower,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    uint256 _repayTokenPrice = LibMoneyMarket01.getPriceUSD(_repayToken, moneyMarketDs);
    uint256 _repaidBorrowingPower = LibMoneyMarket01.usedBorrowingPower(
      _repaidAmount,
      _repayTokenPrice,
      moneyMarketDs.tokenConfigs[_repayToken].borrowingFactor
    );
    if (_repaidBorrowingPower * LibMoneyMarket01.MAX_BPS > (_usedBorrowingPower * moneyMarketDs.maxLiquidateBps)) {
      revert LiquidationFacet_RepayAmountExceedThreshold();
    }
  }

  function _calculateActualRepayAmountAndFee(
    InternalLiquidationCallParams memory params,
    uint256 _repayAmountBefore,
    uint256 _expectMaxRepayAmount,
    uint256 _maxFeePossible
  ) internal view returns (uint256 _actualRepayAmount, uint256 _actualLiquidationFee) {
    uint256 _amountFromLiquidationStrat = IERC20(params.repayToken).balanceOf(address(this)) - _repayAmountBefore;
    _actualLiquidationFee = (_amountFromLiquidationStrat * _maxFeePossible) / _expectMaxRepayAmount;
    _actualRepayAmount = _amountFromLiquidationStrat - _actualLiquidationFee;
  }
}
