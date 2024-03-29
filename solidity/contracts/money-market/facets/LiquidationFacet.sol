// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// ---- Libraries ---- //
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibConstant } from "../libraries/LibConstant.sol";
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
    uint256 _feeToTreasury
  );

  struct RepurchaseLocalVars {
    address subAccount;
    uint256 totalBorrowingPower;
    uint256 usedBorrowingPower;
    uint256 repayAmountWithFee;
    uint256 repurchaseFeeToProtocol;
    uint256 repurchaseRewardBps;
    uint256 repayAmountWithoutFee;
    uint256 repayTokenPrice;
    bool isRepurchaseAll;
  }

  struct LiquidationLocalVars {
    address subAccount;
    uint256 maxPossibleRepayAmount;
    uint256 maxPossibleFee;
    uint256 expectedMaxRepayAmount;
    uint256 repaidAmount;
    uint256 actualLiquidationFee;
    uint256 collatSold;
    uint256 collatTokenBalanceBefore;
    uint256 repayTokenBalaceBefore;
    uint256 usedBorrowingPower;
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
  /// @return _collatAmountOut The amount of collateral returned to repurchaser
  function repurchase(
    address _account,
    uint256 _subAccountId,
    address _repayToken,
    address _collatToken,
    uint256 _desiredRepayAmount
  ) external nonReentrant returns (uint256 _collatAmountOut) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    // We disallow repurchaser to be the same address with the account owner
    // While our contract wouldn't suffer such an action, it's better to be on the safe side
    // note: refer the original issue in "Compound's self liquidation bug"
    if (msg.sender == _account) {
      revert LiquidationFacet_Unauthorized();
    }

    RepurchaseLocalVars memory _vars;

    _vars.subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    // Accrue all debt tokens under subaccount
    // Because used borrowing power is calculated from all debt token of the subaccount
    LibMoneyMarket01.accrueBorrowedPositionsOf(_vars.subAccount, moneyMarketDs);

    _vars.totalBorrowingPower = LibMoneyMarket01.getTotalBorrowingPower(_vars.subAccount, moneyMarketDs);
    (_vars.usedBorrowingPower, ) = LibMoneyMarket01.getTotalUsedBorrowingPower(_vars.subAccount, moneyMarketDs);
    // Revert if position is not repurchasable (borrowingPower / usedBorrowingPower >= 1)
    if (_vars.totalBorrowingPower >= _vars.usedBorrowingPower) {
      revert LiquidationFacet_Healthy();
    }

    // Cap repurchase amount if needed and calculate fee
    // Fee is calculated from repaid amount
    //
    // formulas:
    //     maxAmountRepurchaseable  = currentDebt * (1 + fee)
    //     repurchaseFee            = repayAmountWithFee - repayAmountWithoutFee
    //     if desiredRepayAmount > maxAmountRepurchaseable
    //        repayAmountWithFee    = maxAmountRepurchaseable
    //        repayAmountWithoutFee = currentDebt
    //     else
    //        repayAmountWithFee    = desiredRepayAmount
    //        repayAmountWithoutFee = desiredRepayAmount / (1 + fee)
    //
    // calculation example:
    //     assume 1 eth = 2000 USD, 10% repurchase fee, ignore collat,borrowingFactor, no premium
    //     collateral: 2000 USDC
    //     debt      : 1 eth
    //     maxAmountRepurchaseable = currentDebt * (1 + fee)
    //                             = 1 * (1 + 0.1) = 1.1 eth
    //
    //     ex 1: desiredRepayAmount > maxAmountRepurchaseable
    //     input : desiredRepayAmount = 1.2 eth
    //     repayAmountWithFee    = maxAmountRepurchaseable = 1.1 eth
    //     repayAmountWithoutFee = currentDebt = 1 eth
    //     repurchaseFee         = repayAmountWithFee - repayAmountWithoutFee
    //                           = 1.1 - 1 = 0.1 eth
    //
    //     ex 2: desiredRepayAmount < currentDebt
    //     input : desiredRepayAmount = 0.9 eth
    //     repayAmountWithFee    = desiredRepayAmount = 0.9 eth
    //     repayAmountWithoutFee = desiredRepayAmount / (1 + fee)
    //                           = 0.9 / (1 + 0.1) = 0.818181.. eth
    //     repurchaseFee         = repayAmountWithFee - repayAmountWithoutFee
    //                           = 0.9 - 0.818181... = 0.0818181... eth
    //
    //     ex 3: desiredRepayAmount == currentDebt
    //     input : desiredRepayAmount = 1 eth
    //     repayAmountWithFee    = desiredRepayAmount = 1 eth
    //     repayAmountWithoutFee = desiredRepayAmount / (1 + fee)
    //                           = 1 / (1 + 0.1) = 0.909090.. eth
    //     repurchaseFee         = repayAmountWithFee - repayAmountWithoutFee
    //                           = 1 - 0.909090... = 0.0909090... eth
    //
    //     ex 4: currentDebt < desiredRepayAmount < maxAmountRepurchaseable
    //     input : desiredRepayAmount = 1.05 eth
    //     repayAmountWithFee = desiredRepayAmount = 1.05 eth
    //     repayAmountWithoutFee = desiredRepayAmount / (1 + fee)
    //                           = 1.05 / (1 + 0.1) = 0.9545454... eth
    //     repurchaseFee         = repayAmountWithFee - repayAmountWithoutFee
    //                           = 1.05 - 0.9545454... = 0.09545454... eth
    //
    {
      (, uint256 _currentDebtAmount) = LibMoneyMarket01.getOverCollatDebtShareAndAmountOf(
        _vars.subAccount,
        _repayToken,
        moneyMarketDs
      );
      uint256 _maxAmountRepurchaseable = (_currentDebtAmount * (moneyMarketDs.repurchaseFeeBps + LibConstant.MAX_BPS)) /
        LibConstant.MAX_BPS;

      if (_desiredRepayAmount > _maxAmountRepurchaseable) {
        _vars.repayAmountWithFee = _maxAmountRepurchaseable;
        _vars.repayAmountWithoutFee = _currentDebtAmount;
        // set flag `isRepurchaseAll` = true for further use in `_actualRepayAmountWithoutFee` calculation
        _vars.isRepurchaseAll = true;
      } else {
        _vars.repayAmountWithFee = _desiredRepayAmount;
        _vars.repayAmountWithoutFee =
          (_desiredRepayAmount * LibConstant.MAX_BPS) /
          (moneyMarketDs.repurchaseFeeBps + LibConstant.MAX_BPS);
      }

      _vars.repurchaseFeeToProtocol = _vars.repayAmountWithFee - _vars.repayAmountWithoutFee;
    }

    _vars.repayTokenPrice = LibMoneyMarket01.getPriceUSD(_repayToken, moneyMarketDs);

    // Revert if repayment exceeds threshold (repayment > maxLiquidateThreshold * usedBorrowingPower)
    _validateBorrowingPower(_repayToken, _vars.repayAmountWithoutFee, _vars.usedBorrowingPower, moneyMarketDs);

    // Get dynamic repurchase reward to further incentivize repurchase
    _vars.repurchaseRewardBps = moneyMarketDs.repurchaseRewardModel.getFeeBps(
      _vars.totalBorrowingPower,
      _vars.usedBorrowingPower
    );

    // Calculate payout for repurchaser (collateral with premium)
    {
      uint256 _collatTokenPrice = LibMoneyMarket01.getPriceUSD(_collatToken, moneyMarketDs);

      uint256 _repayTokenPriceWithPremium = (_vars.repayTokenPrice *
        (LibConstant.MAX_BPS + _vars.repurchaseRewardBps)) / LibConstant.MAX_BPS;

      // collatAmountOut = repayAmount * repayTokenPriceWithPremium / collatTokenPrice
      _collatAmountOut =
        (_vars.repayAmountWithFee *
          _repayTokenPriceWithPremium *
          moneyMarketDs.tokenConfigs[_repayToken].to18ConversionFactor) /
        (_collatTokenPrice * moneyMarketDs.tokenConfigs[_collatToken].to18ConversionFactor);

      // revert if subAccount collat is not enough to cover desired repay amount
      // this could happen when there are multiple small collat and one large debt
      // ex. assume 1 eth = 2000 USD, no repurchase fee or premium, ignore collat,borrowingFactor
      //     collateral : 1000 USDT, 1000 USDC
      //     debt       : 1 eth
      //     input      : desiredRepayAmount = 0.6 eth, collatToken = USDC
      //     collatAmountOut = repayAmount * repayTokenPrice / collatTokenPrice
      //                     = 0.6 * 2000 / 1 = 1200 USDC
      //     this should revert since there is not enough USDC collateral to be repurchased
      if (_collatAmountOut > moneyMarketDs.subAccountCollats[_vars.subAccount].getAmount(_collatToken)) {
        revert LiquidationFacet_InsufficientAmount();
      }
    }

    /////////////////////////////////
    // EFFECTS & INTERACTIONS
    /////////////////////////////////

    // Transfer repay token in
    // In case of token with fee on transfer, debt would be repaid by amount after transfer fee
    // which won't be able to repurchase entire position
    // repaidAmount = amountReceived - repurchaseFee
    //
    _vars.repayAmountWithFee = _calculateRepayAmountWithFeeRoundUp(_repayToken, _vars, moneyMarketDs);

    uint256 _actualRepayAmountWithoutFee = LibMoneyMarket01.unsafePullTokens(
      _repayToken,
      msg.sender,
      _vars.repayAmountWithFee
    ) - _vars.repurchaseFeeToProtocol;

    // Remove subAccount debt
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
    // need to call removeCollat which might withdraw from miniFL to be able to transfer to repurchaser
    LibMoneyMarket01.removeCollatFromSubAccount(
      _account,
      _vars.subAccount,
      _collatToken,
      _collatAmountOut,
      false,
      moneyMarketDs
    );

    // Increase reserves balance with repaid tokens
    // Safe to use unchecked because _actualRepayAmountWithoutFee is derived from balanceOf
    unchecked {
      moneyMarketDs.reserves[_repayToken] += _actualRepayAmountWithoutFee;
    }

    // Transfer collat token with premium back to repurchaser
    IERC20(_collatToken).safeTransfer(msg.sender, _collatAmountOut);
    // Transfer protocol's repurchase fee to treasury
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
      (_collatAmountOut * _vars.repurchaseRewardBps) / LibConstant.MAX_BPS
    );
  }

  /// @notice Liquidate the collateral token in exchange of the debt token
  ///
  ///         liquidation process
  ///           1) withdraw specified collateral of subAccount and withdraw from MiniFL staking if applicable
  ///           2) send the collateral to strategy to prepare for liquidation
  ///           3) call `executeLiquidation` on strategy
  ///               - strategy convert collateral to repay token
  ///               - strategy transfer converted repay token and leftover collateral (if any) back to diamond
  ///           4) calculate actual repayment and fees (fee to protocol and caller) based on
  ///              amount received from strategy
  ///           5) check if the repayment violate maximum amount allowed to be liquidated in single tx
  ///           6) update states
  ///               - increase repay token reserve by amount repaid
  ///               - reduce subAccount's debt by amount repaid
  ///               - if any collateral left, add them back to subAccount and stake to MiniFL if applicable
  ///           7) transfer fee to treasury and caller
  ///
  /// @param _liquidationStrat The address of strategy used in liqudation
  /// @param _account The account to be repurchased
  /// @param _subAccountId The index to derive the subaccount
  /// @param _repayToken The token that will be repurchase and repay the debt
  /// @param _collatToken The collateral token that will be used for exchange
  /// @param _collatAmount The amount of collateral to liquidate
  /// @param _minReceive Minimum amount expected from liquidation in repayToken
  function liquidationCall(
    address _liquidationStrat,
    address _account,
    uint256 _subAccountId,
    address _repayToken,
    address _collatToken,
    uint256 _collatAmount,
    uint256 _minReceive,
    bytes memory _data
  ) external nonReentrant liquidateExec {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    // Revert if liquidationStrat or caller is not whitelisted
    if (!moneyMarketDs.liquidationStratOk[_liquidationStrat] || !moneyMarketDs.liquidatorsOk[msg.sender]) {
      revert LiquidationFacet_Unauthorized();
    }

    if (_collatAmount == 0) {
      revert LiquidationFacet_InvalidParams();
    }

    LiquidationLocalVars memory _vars;

    _vars.subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);
    // Revert if subAccount doesn't have collateral to be liquidated
    if (moneyMarketDs.subAccountCollats[_vars.subAccount].getAmount(_collatToken) == 0) {
      revert LiquidationFacet_CollateralNotExist();
    }

    // Accrue all debt tokens under subaccount
    // Because used borrowing power is calculated from all debt token of the subaccount
    LibMoneyMarket01.accrueBorrowedPositionsOf(_vars.subAccount, moneyMarketDs);

    {
      uint256 _borrowingPower = LibMoneyMarket01.getTotalBorrowingPower(_vars.subAccount, moneyMarketDs);
      (_vars.usedBorrowingPower, ) = LibMoneyMarket01.getTotalUsedBorrowingPower(_vars.subAccount, moneyMarketDs);
      // Revert if position is not liquidatable (borrowingPower / usedBorrowingPower > 1 / liquidationThreshold)
      // This threshold should be lower than repurchase (liquidationThreshold > 1)
      // because position must be repurchasable before liquidatable
      if ((_vars.usedBorrowingPower * LibConstant.MAX_BPS) < _borrowingPower * moneyMarketDs.liquidationThresholdBps) {
        revert LiquidationFacet_Healthy();
      }
    }

    // Remove all collateral from the subaccount first
    // If applicable, this will withdraw staked collateral from miniFL
    // so that it can be transfered to strategy contract
    LibMoneyMarket01.removeCollatFromSubAccount(
      _account,
      _vars.subAccount,
      _collatToken,
      _collatAmount,
      false,
      moneyMarketDs
    );

    // Cache the balance of tokens before executing strategy contract
    // This will be used to find the actual collateral used and repay token back from the strategy
    _vars.collatTokenBalanceBefore = IERC20(_collatToken).balanceOf(address(this));
    _vars.repayTokenBalaceBefore = IERC20(_repayToken).balanceOf(address(this));

    // Send all collats under subaccount to strategy
    IERC20(_collatToken).safeTransfer(_liquidationStrat, _collatAmount);

    // Calculated repayToken amount expected from liquidation
    // Cap repay amount to current debt if input exceeds it
    // maxPossibleRepayAmount = min(repayAmount, currentDebt)
    {
      uint256 _debtShare = moneyMarketDs.subAccountDebtShares[_vars.subAccount].getAmount(_repayToken);
      // for ib debtValue is in ib shares not in underlying
      _vars.maxPossibleRepayAmount = LibShareUtil.shareToValue(
        _debtShare,
        moneyMarketDs.overCollatDebtValues[_repayToken],
        moneyMarketDs.overCollatDebtShares[_repayToken]
      );
    }
    _vars.maxPossibleFee = (_vars.maxPossibleRepayAmount * moneyMarketDs.liquidationFeeBps) / LibConstant.MAX_BPS;

    _vars.expectedMaxRepayAmount = _vars.maxPossibleRepayAmount + _vars.maxPossibleFee;

    // Call executeLiquidation on strategy
    // Strategy will convert collatToken to repayToken and send back here
    ILiquidationStrategy(_liquidationStrat).executeLiquidation(
      _collatToken,
      _repayToken,
      _collatAmount,
      _vars.expectedMaxRepayAmount,
      _minReceive,
      _data
    );

    // Calculate actual repayment by comparing balance of repayToken before and after liquidation
    // actualLiquidationFee = amountFromStrat * liquidationFee
    //                      = amountFromStrat * maxPossibleFee / expectedMaxRepayAmount
    // repaidAmount = amountFromStrat - actualLiquidationFee
    {
      // calculate the repaid amount returned from strategy
      uint256 _amountFromLiquidationStrat = IERC20(_repayToken).balanceOf(address(this)) - _vars.repayTokenBalaceBefore;
      // revert if executing a strategy result in excessive market selling
      // This implied that the collateral value is greater than the debt
      // It is not eligible for liquidation and should be repurchased instead
      if (_amountFromLiquidationStrat > _vars.expectedMaxRepayAmount) {
        revert LiquidationFacet_TooMuchRepayToken();
      }
      // find the actual fee through the rule of three
      // _actualLiquidationFee = maxFee * (_amountFromLiquidationStrat / _expectedMaxRepayAmount)
      _vars.actualLiquidationFee = (_amountFromLiquidationStrat * _vars.maxPossibleFee) / _vars.expectedMaxRepayAmount;

      _vars.repaidAmount = _amountFromLiquidationStrat - _vars.actualLiquidationFee;
    }

    // Revert if repayment exceeds threshold (repayment > maxLiquidateThreshold * usedBorrowingPower)
    _validateBorrowingPower(_repayToken, _vars.repaidAmount, _vars.usedBorrowingPower, moneyMarketDs);

    // Increase repayToken reserve balance
    // Safe to use unchecked because repaidAmount is derived from balanceOf
    unchecked {
      moneyMarketDs.reserves[_repayToken] += _vars.repaidAmount;
    }
    {
      uint256 _sharesToRemove = LibShareUtil.valueToShare(
        _vars.repaidAmount,
        moneyMarketDs.overCollatDebtShares[_repayToken],
        moneyMarketDs.overCollatDebtValues[_repayToken]
      );
      // Remove repaid debt from subAccount
      LibMoneyMarket01.removeOverCollatDebtFromSubAccount(
        _account,
        _vars.subAccount,
        _repayToken,
        _sharesToRemove,
        _vars.repaidAmount,
        moneyMarketDs
      );
    }

    // Calculate the actual collateral used in liquidation strategy by comparing balance before and after
    _vars.collatSold = _vars.collatTokenBalanceBefore - IERC20(_collatToken).balanceOf(address(this));

    // Add remaining collateral back to the subaccount since we have removed specified amount of
    // collateral earlier. This should deposit collateral back to miniFL if applicable
    if (_collatAmount > _vars.collatSold) {
      unchecked {
        LibMoneyMarket01.addCollatToSubAccount(
          _account,
          _vars.subAccount,
          _collatToken,
          _collatAmount - _vars.collatSold,
          false,
          moneyMarketDs
        );
      }
    }

    IERC20(_repayToken).safeTransfer(moneyMarketDs.liquidationTreasury, _vars.actualLiquidationFee);

    // Write off all debts under the subaccount if there's no more collateral
    // This would result in realizing the bad debts to lenders
    LibMoneyMarket01.writeOffBadDebt(_account, _vars.subAccount, moneyMarketDs);

    emit LogLiquidate(
      msg.sender,
      _liquidationStrat,
      _account,
      _subAccountId,
      _repayToken,
      _collatToken,
      _vars.repaidAmount,
      _vars.collatSold,
      _vars.actualLiquidationFee
    );
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
    // Revert if repayment exceeds threshold (repayment > maxLiquidateThreshold * usedBorrowingPower)
    if (_repaidBorrowingPower * LibConstant.MAX_BPS > (_usedBorrowingPower * moneyMarketDs.maxLiquidateBps)) {
      revert LiquidationFacet_RepayAmountExceedThreshold();
    }
  }

  function _calculateRepayAmountWithFeeRoundUp(
    address _repayToken,
    RepurchaseLocalVars memory _vars,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _repayAmountWithFee) {
    // To prevent precision loss and leaving 1 wei debt in subAccount when user repurchase the entire debt
    // assume totalDebtWithFee = 10 wei
    // _repayAmountWithoutFee = 10 wei, overCollatDebtShares = 10 wei, overCollatDebtValues = 15 wei

    // fully repurchase without adding extra wei
    // _repayShare = 10 * 10 / 15 = 6.66666666667 => round down to 6 shares
    // _repayShareToValue = 6 * 15 / 10 = 9 wei => result in 1 wei debt leftover

    // fully repurchase with adding extra wei
    // _repayShare = 10 * 10 / 15 = 6.66666666667
    // _repayAmountWithoutFee = 11 wei
    // _newRepayShare = 11 * 10 / 15 = 7.33333333333 =>  round down to 7 shares
    // _newRepayShareToValue = 7 * 15 / 10 = 10.5 => round down to 10 wei and repay all debt
    _repayAmountWithFee = _vars.repayAmountWithFee;
    if (_vars.isRepurchaseAll) {
      uint256 _repayAmountWithoutFee = _vars.repayAmountWithFee - _vars.repurchaseFeeToProtocol;
      uint256 _actualRepayShare = LibShareUtil.valueToShare(
        _repayAmountWithoutFee,
        moneyMarketDs.overCollatDebtShares[_repayToken],
        moneyMarketDs.overCollatDebtValues[_repayToken]
      );
      uint256 _expectRepayShare = LibShareUtil.valueToShareRoundingUp(
        _repayAmountWithoutFee,
        moneyMarketDs.overCollatDebtShares[_repayToken],
        moneyMarketDs.overCollatDebtValues[_repayToken]
      );

      // Adding repayAmountWithFee by 1 wei when there is a precision loss in _actualRepayShare
      if (_actualRepayShare + 1 == _expectRepayShare) {
        _repayAmountWithFee += 1;
      }
    }
  }
}
