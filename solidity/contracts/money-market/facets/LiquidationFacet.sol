// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// ---- Libraries ---- //
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";
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

  event LogRepurchase(
    address indexed _repurchaser,
    address _account,
    uint256 _subAccountId,
    address _repayToken,
    address _collatToken,
    uint256 _actualRepayAmountWithoutFee,
    uint256 _collatAmountOut,
    uint256 _feeToTreasury,
    uint256 _repurchaseRewardToCaller
  );
  event LogLiquidate(
    address indexed _caller,
    address indexed _liquidationStrategy,
    address _account,
    uint256 _subAccountId,
    address _repayToken,
    address _collatToken,
    uint256 _amountDebtRepaid,
    uint256 _amountCollatLiquidated,
    uint256 _feeToTreasury,
    uint256 _feeToLiquidator
  );

  struct InternalLiquidationCallParams {
    address liquidationStrat;
    address account;
    uint256 subAccountId;
    address subAccount;
    address repayToken;
    address collatToken;
    uint256 repayAmount;
    uint256 usedBorrowingPower;
    uint256 minReceive;
    uint256 subAccountCollatAmount;
  }

  struct LiquidationLocalVars {
    uint256 maxPossibleRepayAmount;
    uint256 maxPossibleFee;
    uint256 expectedMaxRepayAmount;
    uint256 repaidAmount;
    uint256 actualLiquidationFee;
    uint256 feeToLiquidator;
    uint256 feeToTreasury;
    uint256 collatSold;
    uint256 collatTokenBalanceBefore;
    uint256 repayTokenBalaceBefore;
  }

  struct RepurchaseLocalVars {
    address subAccount;
    uint256 totalBorrowingPower;
    uint256 usedBorrowingPower;
    uint256 repayAmountWithFee;
    uint256 repurchaseFeeToProtocol;
    uint256 repurchaseRewardBps;
    uint256 repayAmountWithoutFee;
    uint256 repayTokenPrice;
  }

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  modifier liquidateExec() {
    LibReentrancyGuard.ReentrancyGuardDiamondStorage storage reentrancyGuardDs = LibReentrancyGuard
      .reentrancyGuardDiamondStorage();
    reentrancyGuardDs.liquidateExec = LibReentrancyGuard._ENTERED;
    _;
    reentrancyGuardDs.liquidateExec = LibReentrancyGuard._NOT_ENTERED;
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

    if (msg.sender != tx.origin && !moneyMarketDs.repurchasersOk[msg.sender]) {
      revert LiquidationFacet_Unauthorized();
    }

    RepurchaseLocalVars memory _vars;

    _vars.subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    LibMoneyMarket01.accrueBorrowedPositionsOf(_vars.subAccount, moneyMarketDs);

    // revert if position is healthy
    _vars.totalBorrowingPower = LibMoneyMarket01.getTotalBorrowingPower(_vars.subAccount, moneyMarketDs);
    (_vars.usedBorrowingPower, ) = LibMoneyMarket01.getTotalUsedBorrowingPower(_vars.subAccount, moneyMarketDs);
    if (_vars.totalBorrowingPower >= _vars.usedBorrowingPower) {
      revert LiquidationFacet_Healthy();
    }

    // cap repurchase amount if needed and calculate fee
    {
      // _maxAmountRepurchaseable = current debt + fee
      (, uint256 _currentDebtAmount) = LibMoneyMarket01.getOverCollatDebtShareAndAmountOf(
        _vars.subAccount,
        _repayToken,
        moneyMarketDs
      );
      uint256 _maxAmountRepurchaseable = (_currentDebtAmount *
        (moneyMarketDs.repurchaseFeeBps + LibMoneyMarket01.MAX_BPS)) / LibMoneyMarket01.MAX_BPS;

      // repay amount is capped if try to repay more than outstanding debt + fee
      if (_desiredRepayAmount > _maxAmountRepurchaseable) {
        // repayAmountWithFee = _currentDebtAmount + fee
        _vars.repayAmountWithFee = _maxAmountRepurchaseable;
        // calculate like this so we can close entire debt without dust
        // repayAmountWithoutFee = _currentDebtAmount = repayAmountWithFee * _currentDebtAmount / _maxAmountRepurchaseable
        _vars.repayAmountWithoutFee = _currentDebtAmount;
      } else {
        _vars.repayAmountWithFee = _desiredRepayAmount;
        _vars.repayAmountWithoutFee =
          (_desiredRepayAmount * (LibMoneyMarket01.MAX_BPS - moneyMarketDs.repurchaseFeeBps)) /
          LibMoneyMarket01.MAX_BPS;
      }

      _vars.repurchaseFeeToProtocol = _vars.repayAmountWithFee - _vars.repayAmountWithoutFee;
    }

    _vars.repayTokenPrice = LibMoneyMarket01.getPriceUSD(_repayToken, moneyMarketDs);

    // revert if repay > x% of totalUsedBorrowingPower
    _validateBorrowingPower(_repayToken, _vars.repayAmountWithoutFee, _vars.usedBorrowingPower, moneyMarketDs);

    _vars.repurchaseRewardBps = moneyMarketDs.repurchaseRewardModel.getFeeBps(
      _vars.totalBorrowingPower,
      _vars.usedBorrowingPower
    );

    // calculate payout (collateral + reward)
    {
      uint256 _collatTokenPrice = LibMoneyMarket01.getPriceUSD(_collatToken, moneyMarketDs);

      uint256 _repayTokenPriceWithPremium = (_vars.repayTokenPrice *
        (LibMoneyMarket01.MAX_BPS + _vars.repurchaseRewardBps)) / LibMoneyMarket01.MAX_BPS;

      // 100(18) * 120 * 1 /
      _collatAmountOut =
        (_vars.repayAmountWithFee *
          _repayTokenPriceWithPremium *
          moneyMarketDs.tokenConfigs[_repayToken].to18ConversionFactor) /
        (_collatTokenPrice * moneyMarketDs.tokenConfigs[_collatToken].to18ConversionFactor);

      // revert if subAccount collat is not enough to cover desired repay amount
      // this could happen when there are multiple small collat and one large debt
      if (_collatAmountOut > moneyMarketDs.subAccountCollats[_vars.subAccount].getAmount(_collatToken)) {
        revert LiquidationFacet_InsufficientAmount();
      }
    }

    // transfer tokens
    // in case of fee on transfer tokens, debt would be repaid by amount after transfer fee
    // which won't be able to repurchase entire position
    uint256 _actualRepayAmountWithoutFee = LibMoneyMarket01.unsafePullTokens(
      _repayToken,
      msg.sender,
      _vars.repayAmountWithFee
    ) - _vars.repurchaseFeeToProtocol;

    // update states
    LibMoneyMarket01.removeOverCollatDebtFromSubAccount(
      _account,
      _vars.subAccount,
      _repayToken,
      LibShareUtil.valueToShare(
        _actualRepayAmountWithoutFee,
        moneyMarketDs.overCollatDebtShares[_repayToken],
        moneyMarketDs.overCollatDebtValues[_repayToken]
      ),
      _actualRepayAmountWithoutFee,
      moneyMarketDs
    );
    LibMoneyMarket01.removeCollatFromSubAccount(
      _account,
      _vars.subAccount,
      _collatToken,
      _collatAmountOut,
      moneyMarketDs
    );

    moneyMarketDs.reserves[_repayToken] += _actualRepayAmountWithoutFee;

    IERC20(_collatToken).safeTransfer(msg.sender, _collatAmountOut);
    IERC20(_repayToken).safeTransfer(moneyMarketDs.liquidationTreasury, _vars.repurchaseFeeToProtocol);

    emit LogRepurchase(
      msg.sender,
      _account,
      _subAccountId,
      _repayToken,
      _collatToken,
      _actualRepayAmountWithoutFee,
      _collatAmountOut,
      _vars.repurchaseFeeToProtocol,
      (_collatAmountOut * _vars.repurchaseRewardBps) / LibMoneyMarket01.MAX_BPS
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
    uint256 _minReceive
  ) external nonReentrant liquidateExec {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    if (!moneyMarketDs.liquidationStratOk[_liquidationStrat] || !moneyMarketDs.liquidatorsOk[msg.sender]) {
      revert LiquidationFacet_Unauthorized();
    }

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);
    uint256 _collatAmount = moneyMarketDs.subAccountCollats[_subAccount].getAmount(_collatToken);

    if (_collatAmount == 0) {
      revert LiquidationFacet_InsufficientAmount();
    }

    LibMoneyMarket01.accrueBorrowedPositionsOf(_subAccount, moneyMarketDs);

    // 1. check if position is underwater and can be liquidated
    uint256 _borrowingPower = LibMoneyMarket01.getTotalBorrowingPower(_subAccount, moneyMarketDs);
    (uint256 _usedBorrowingPower, ) = LibMoneyMarket01.getTotalUsedBorrowingPower(_subAccount, moneyMarketDs);
    if ((_usedBorrowingPower * LibMoneyMarket01.MAX_BPS) < _borrowingPower * moneyMarketDs.liquidationThresholdBps) {
      revert LiquidationFacet_Healthy();
    }

    InternalLiquidationCallParams memory _params = InternalLiquidationCallParams({
      liquidationStrat: _liquidationStrat,
      account: _account,
      subAccountId: _subAccountId,
      subAccount: _subAccount,
      repayToken: _repayToken,
      collatToken: _collatToken,
      repayAmount: _repayAmount,
      usedBorrowingPower: _usedBorrowingPower,
      minReceive: _minReceive,
      subAccountCollatAmount: _collatAmount
    });

    _liquidationCall(_params, moneyMarketDs);
  }

  function _liquidationCall(
    InternalLiquidationCallParams memory _params,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    LiquidationLocalVars memory _vars;

    // remove all collateral from the subaccount first
    // In case the collateral is ibToken and currently staking in miniFL
    // This will withdraw from miniFL so that the collat token can be transfered to strategy contract
    LibMoneyMarket01.removeCollatFromSubAccount(
      _params.account,
      _params.subAccount,
      _params.collatToken,
      _params.subAccountCollatAmount,
      moneyMarketDs
    );

    // cache the balance of tokens before executing strategy contract
    // this will be used to find the actual collateral used and repay token back from the strategy
    _vars.collatTokenBalanceBefore = IERC20(_params.collatToken).balanceOf(address(this));
    _vars.repayTokenBalaceBefore = IERC20(_params.repayToken).balanceOf(address(this));

    // 2. send all collats under subaccount to strategy
    IERC20(_params.collatToken).safeTransfer(_params.liquidationStrat, _params.subAccountCollatAmount);

    // 3. call executeLiquidation on strategy
    _vars.maxPossibleRepayAmount = _calculateMaxPossibleRepayAmount(
      _params.subAccount,
      _params.repayToken,
      _params.repayAmount,
      moneyMarketDs
    );
    _vars.maxPossibleFee = (_vars.maxPossibleRepayAmount * moneyMarketDs.liquidationFeeBps) / LibMoneyMarket01.MAX_BPS;

    unchecked {
      _vars.expectedMaxRepayAmount = _vars.maxPossibleRepayAmount + _vars.maxPossibleFee;
    }

    ILiquidationStrategy(_params.liquidationStrat).executeLiquidation(
      _params.collatToken,
      _params.repayToken,
      _params.subAccountCollatAmount,
      _vars.expectedMaxRepayAmount,
      _params.minReceive
    );

    // 4. check repaid amount, take fees, and update states
    (_vars.repaidAmount, _vars.actualLiquidationFee) = _calculateActualRepayAmountAndFee(
      _params.repayToken,
      _vars.repayTokenBalaceBefore,
      _vars.expectedMaxRepayAmount,
      _vars.maxPossibleFee
    );

    // 5. split fee between liquidator and treasury
    _vars.feeToLiquidator =
      (_vars.actualLiquidationFee * moneyMarketDs.liquidationRewardBps) /
      LibMoneyMarket01.MAX_BPS;
    _vars.feeToTreasury = _vars.actualLiquidationFee - _vars.feeToLiquidator;

    _validateBorrowingPower(_params.repayToken, _vars.repaidAmount, _params.usedBorrowingPower, moneyMarketDs);

    moneyMarketDs.reserves[_params.repayToken] += _vars.repaidAmount;

    // give priority to fee
    LibMoneyMarket01.removeOverCollatDebtFromSubAccount(
      _params.account,
      _params.subAccount,
      _params.repayToken,
      LibShareUtil.valueToShare(
        _vars.repaidAmount,
        moneyMarketDs.overCollatDebtShares[_params.repayToken],
        moneyMarketDs.overCollatDebtValues[_params.repayToken]
      ),
      _vars.repaidAmount,
      moneyMarketDs
    );

    // Calculate the actual collateral used in liquidation strategy by comparing balance before and after
    _vars.collatSold = _vars.collatTokenBalanceBefore - IERC20(_params.collatToken).balanceOf(address(this));

    // add remaining collateral back to the subaccount since we have removed all collateral earlier
    // this should also deposit collateral back to miniFL if applicable
    LibMoneyMarket01.addCollatToSubAccount(
      _params.account,
      _params.subAccount,
      _params.collatToken,
      _params.subAccountCollatAmount - _vars.collatSold,
      moneyMarketDs
    );

    IERC20(_params.repayToken).safeTransfer(msg.sender, _vars.feeToLiquidator);
    IERC20(_params.repayToken).safeTransfer(moneyMarketDs.liquidationTreasury, _vars.feeToTreasury);

    emit LogLiquidate(
      msg.sender,
      _params.liquidationStrat,
      _params.account,
      _params.subAccountId,
      _params.repayToken,
      _params.collatToken,
      _vars.repaidAmount,
      _vars.collatSold,
      _vars.feeToTreasury,
      _vars.feeToLiquidator
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
      moneyMarketDs.tokenConfigs[_repayToken].borrowingFactor,
      moneyMarketDs.tokenConfigs[_repayToken].to18ConversionFactor
    );
    if (_repaidBorrowingPower * LibMoneyMarket01.MAX_BPS > (_usedBorrowingPower * moneyMarketDs.maxLiquidateBps)) {
      revert LiquidationFacet_RepayAmountExceedThreshold();
    }
  }

  function _calculateActualRepayAmountAndFee(
    address _repayToken,
    uint256 _repayTokenBalanceBefore,
    uint256 _expectedMaxRepayAmount,
    uint256 _maxFeePossible
  ) internal view returns (uint256 _actualRepayAmount, uint256 _actualLiquidationFee) {
    // strategy will only swap exactly less than or equal to _expectedMaxRepayAmount
    uint256 _amountFromLiquidationStrat = IERC20(_repayToken).balanceOf(address(this)) - _repayTokenBalanceBefore;
    // find the actual fee through the rule of three
    // _actualLiquidationFee = maxFee * (_amountFromLiquidationStrat / _expectedMaxRepayAmount)
    _actualLiquidationFee = (_amountFromLiquidationStrat * _maxFeePossible) / _expectedMaxRepayAmount;
    unchecked {
      _actualRepayAmount = _amountFromLiquidationStrat - _actualLiquidationFee;
    }
  }
}
