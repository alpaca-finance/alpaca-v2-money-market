// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// ---- Libraries ---- //
import { LibSafeToken } from "../money-market/libraries/LibSafeToken.sol";

// ---- Interfaces ---- //
import { IMoneyMarketAccountManager } from "../interfaces/IMoneyMarketAccountManager.sol";
import { ILendFacet } from "../money-market/interfaces/ILendFacet.sol";
import { IViewFacet } from "../money-market/interfaces/IViewFacet.sol";
import { IBorrowFacet } from "../money-market/interfaces/IBorrowFacet.sol";
import { ICollateralFacet } from "../money-market/interfaces/ICollateralFacet.sol";
import { IInterestBearingToken } from "../money-market/interfaces/IInterestBearingToken.sol";
import { IERC20 } from "../money-market/interfaces/IERC20.sol";

contract MoneyMarketAccountManager is IMoneyMarketAccountManager {
  using LibSafeToken for IERC20;

  address moneyMarketDiamond;

  constructor(address _moneyMarketDiamond) {
    // sanity call, should revert if the input didn't implement
    // this particular interface
    IViewFacet(_moneyMarketDiamond).getMinDebtSize();
    moneyMarketDiamond = _moneyMarketDiamond;
  }

  function depositAndAddCollateral(
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external {
    // pull funds from caller and deposit to money market
    (address _ibToken, uint256 _amountReceived) = _deposit(_token, _amount);

    // Use the received ibToken and put it as a colltaral in given subaccount id
    // expecting that all of the received ibToken successfully deposited as collateral
    IERC20(_ibToken).safeApprove(moneyMarketDiamond, _amount);
    ICollateralFacet(moneyMarketDiamond).addCollateral(msg.sender, _subAccountId, _ibToken, _amountReceived);
    IERC20(_ibToken).safeApprove(moneyMarketDiamond, 0);
  }

  function removeCollateralAndWithdraw(
    uint256 _subAccountId,
    address _ibToken,
    uint256 _removeAmount
  ) external {}

  function depositAndStake(address _token, uint256 _amount) external {}

  function unstakeAndWithdraw(address _ibToken, uint256 _amount) external {}

  function borrow(
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external {
    // borrow token out on behalf of caller's subaccount
    IBorrowFacet(moneyMarketDiamond).borrow(msg.sender, _subAccountId, _token, _amount);

    // transfer borrowed token back to caller
    // If there's fee on transfer on the token, generally this should revert
    // unless there has been direct inject of borrow token into this contract
    // prior to this call
    IERC20(_token).safeTransfer(msg.sender, _amount);
  }

  function repay(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _repayAmount,
    uint256 _debtShareToRepay
  ) external {}

  function deposit(address _token, uint256 _amount) external {
    // pull funds from caller and deposit to money market
    (address _ibToken, uint256 _amountReceived) = _deposit(_token, _amount);

    // transfer ibToken received back to caller
    IERC20(_ibToken).safeTransfer(msg.sender, _amountReceived);
  }

  function _deposit(address _token, uint256 _amount) internal returns (address _ibToken, uint256 _amountReceived) {
    // Deduct the fund from caller to this contract
    // assuming that there's no fee on transfer
    IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

    // Get the ibToken address from money market
    // This will be used to transfer the ibToken back to caller
    _ibToken = IViewFacet(moneyMarketDiamond).getIbTokenFromToken(_token);

    // Cache the balance of before interacting with money market
    uint256 _ibBalanceBeforeDeposit = IERC20(_ibToken).balanceOf(address(this));

    // deposit to money market, expecting to get ibToken in return
    // approve money market as it will cal safeTransferFrom to this address
    // reset allowance afterward
    IERC20(_token).safeApprove(moneyMarketDiamond, _amount);
    // If the token has feen on transfer, this should fail as the balance from caller
    // to this account manager is lower than intent amount
    // leadning to ERC20: exceed balance error
    ILendFacet(moneyMarketDiamond).deposit(msg.sender, _token, _amount);
    IERC20(_token).safeApprove(moneyMarketDiamond, 0);

    // calculate the actual ibToken receive from deposit action
    // outstanding ibToken in the contract prior to the deposit action should not be included
    _amountReceived = IERC20(_ibToken).balanceOf(address(this)) - _ibBalanceBeforeDeposit;
  }

  function addCollatFor(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external {
    // Deduct the fund from caller to this contract
    // assuming that there's no fee on transfer
    IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

    // Add collateral on behalf of caller
    IERC20(_token).safeApprove(moneyMarketDiamond, _amount);
    ICollateralFacet(moneyMarketDiamond).addCollateral(_account, _subAccountId, _token, _amount);
    IERC20(_token).safeApprove(moneyMarketDiamond, 0);
  }
}
