// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// ---- Libraries ---- //
import { LibSafeToken } from "../money-market/libraries/LibSafeToken.sol";

// ---- Interfaces ---- //
import { IAccountManager } from "../interfaces/IAccountManager.sol";
import { ILendFacet } from "../money-market/interfaces/ILendFacet.sol";
import { IViewFacet } from "../money-market/interfaces/IViewFacet.sol";
import { IBorrowFacet } from "../money-market/interfaces/IBorrowFacet.sol";
import { ICollateralFacet } from "../money-market/interfaces/ICollateralFacet.sol";
import { IInterestBearingToken } from "../money-market/interfaces/IInterestBearingToken.sol";
import { IERC20 } from "../money-market/interfaces/IERC20.sol";

contract AccountManager is IAccountManager {
  using LibSafeToken for IERC20;

  address moneyMarketDiamond;
  ILendFacet internal lendFacet;
  IViewFacet internal viewFacet;
  IBorrowFacet internal borrowFacet;
  ICollateralFacet internal collateralFacet;

  constructor(address _moneyMarketDiamond) {
    moneyMarketDiamond = _moneyMarketDiamond;
    lendFacet = ILendFacet(_moneyMarketDiamond);
    viewFacet = IViewFacet(_moneyMarketDiamond);
    borrowFacet = IBorrowFacet(_moneyMarketDiamond);
    collateralFacet = ICollateralFacet(_moneyMarketDiamond);
  }

  function depositAndAddCollateral(
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external {
    address _ibToken = viewFacet.getIbTokenFromToken(_token);
    uint256 _ibBalanceBeforeDeposit = IInterestBearingToken(_ibToken).balanceOf(msg.sender);

    IERC20(_token).safeApprove(moneyMarketDiamond, type(uint256).max);
    lendFacet.deposit(msg.sender, _token, _amount);
    IERC20(_token).safeApprove(moneyMarketDiamond, 0);

    uint256 _ibBalanceAfterDeposit = IInterestBearingToken(_ibToken).balanceOf(msg.sender);
    uint256 _collatAmount;
    unchecked {
      _collatAmount = _ibBalanceAfterDeposit - _ibBalanceBeforeDeposit;
    }

    collateralFacet.addCollateral(msg.sender, _subAccountId, _token, _collatAmount);
  }

  function removeCollateralAndWithdraw(
    uint256 _subAccountId,
    address _ibToken,
    uint256 _removeAmount
  ) external {}

  function depositAndStake(address _token, uint256 _amount) external {}

  function unStakeAndWithdraw(address _ibToken, uint256 _amount) external {}

  function borrow(
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external {}

  function repay(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _repayAmount,
    uint256 _debtShareToRepay
  ) external {}
}
