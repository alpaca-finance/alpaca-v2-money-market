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

  // todo: change to IMoneyMarket interface and remove all facet interfaces
  address moneyMarketDiamond;

  constructor(address _moneyMarketDiamond) {
    // sanity call, should revert if the input didn't implement
    // this particular interface
    IViewFacet(_moneyMarketDiamond).getMinDebtSize();
    moneyMarketDiamond = _moneyMarketDiamond;
  }

  /// @notice Deposit a token for lending on behalf of the caller
  /// @param _token The token to lend
  /// @param _amount The amount to lend
  function deposit(address _token, uint256 _amount) external {
    // pull funds from the caller and deposit to money market
    (address _ibToken, uint256 _amountReceived) = _deposit(_token, _amount);

    // transfer ibToken received back to caller
    IERC20(_ibToken).safeTransfer(msg.sender, _amountReceived);
  }

  /// @notice Withdraw the lended token by burning the interest bearing token on bahalf of the caller
  /// @param _ibToken The interest bearing token to burn
  /// @param _ibAmount The amount of interest bearing token to burn
  function withdraw(address _ibToken, uint256 _ibAmount) external {
    // Skio if trying to withdraw 0
    if (_ibAmount != 0) {
      // pull ibToken from the caller
      IERC20(_ibToken).safeTransferFrom(msg.sender, address(this), _ibAmount);

      // Withdraw from MoneyMarket using the ibToken that was funded by the caller
      (address _underlyingToken, uint256 _underlyingAmountReceived) = _withdraw(_ibToken, _ibAmount);

      // Transfer the token back to the caller
      // The _underlyingAmountReceived is expected to be greater than 0
      // as this function won't proceed if input shareAmount is 0
      IERC20(_underlyingToken).safeTransfer(msg.sender, _underlyingAmountReceived);
    }
  }

  /// @notice Add a token to a subaccount as a collateral
  /// @param _account The account to add collateral to
  /// @param _subAccountId An index to derive the subaccount
  /// @param _token The collateral token
  /// @param _amount The amount to add
  function addCollateralFor(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external {
    // Transfer the fund from the caller to this contract
    // assuming that there's no fee on transfer
    IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

    // Add collateral for `_account`
    // This call can revert if added amount makes total collateral exceed maximum collateral capacity
    IERC20(_token).safeApprove(moneyMarketDiamond, _amount);
    ICollateralFacet(moneyMarketDiamond).addCollateral(_account, _subAccountId, _token, _amount);
  }

  /// @notice Remove a collateral token from a subaccount on behalf of the caller
  /// @param _subAccountId An index to derive the subaccount
  /// @param _token The collateral token
  /// @param _amount The amount to remove
  function removeCollateral(
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external {
    // skip if trying to remove 0 as this function won't proceed if input amount is 0
    if (_amount != 0) {
      // Remove caller's collateral from specified subaccount
      // Then transfer all of the amount received back to the caller
      // The amount to be transfer is expected to be greater than 0
      IERC20(_token).safeTransfer(msg.sender, _removeCollateral(_subAccountId, _token, _amount));
    }
  }

  /// @notice Transfer the collateral from one subaccount to another subaccount on behalf of the caller
  /// @param _fromSubAccountId An index to derive the subaccount to transfer from
  /// @param _toSubAccountId An index to derive the subaccount to transfer to
  /// @param _token The token to transfer
  /// @param _amount The amount to transfer
  function transferCollateral(
    uint256 _fromSubAccountId,
    uint256 _toSubAccountId,
    address _token,
    uint256 _amount
  ) external {
    // Simply forward the call
    ICollateralFacet(moneyMarketDiamond).transferCollateral(
      msg.sender,
      _fromSubAccountId,
      _toSubAccountId,
      _token,
      _amount
    );
  }

  /// @notice Deposit a token for lending and add all of ibToken to given subaccount id of the caller
  /// @param _subAccountId An index to derive the subaccount
  /// @param _token The token to lend
  /// @param _amount The amount to lend
  function depositAndAddCollateral(
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external {
    // pull funds from caller and deposit to money market
    (address _ibToken, uint256 _amountReceived) = _deposit(_token, _amount);

    // Use the received ibToken and put it as a colltaral in given subaccount id
    // expecting that all of the received ibToken successfully deposited as collateral
    // This call can revert if added amount makes total collateral exceed maximum collateral capacity
    IERC20(_ibToken).safeApprove(moneyMarketDiamond, _amount);
    ICollateralFacet(moneyMarketDiamond).addCollateral(msg.sender, _subAccountId, _ibToken, _amountReceived);
    IERC20(_ibToken).safeApprove(moneyMarketDiamond, 0);
  }

  /// @notice Remove a collateral token from a subaccount and withdraw ibToken
  /// @param _subAccountId An index to derive the subaccount
  /// @param _ibToken The collateral token specifically in ibToken form
  /// @param _amount The amount to remove
  function removeCollateralAndWithdraw(
    uint256 _subAccountId,
    address _ibToken,
    uint256 _amount
  ) external {
    // Skip if trying to remove 0
    // The _underlyingAmountReceived is expected to be greater than 0
    // making the ERC20.transfer impossible to revert on transfer 0 amount
    if (_amount != 0) {
      // Execute remove collateral first
      // Then withdraw all of the ibToken received from removal of collateral
      (address _underlyingToken, uint256 _underlyingAmountReceived) = _withdraw(
        _ibToken,
        _removeCollateral(_subAccountId, _ibToken, _amount)
      );

      IERC20(_underlyingToken).safeTransfer(msg.sender, _underlyingAmountReceived);
    }
  }

  function depositAndStake(address _token, uint256 _amount) external {}

  function unstakeAndWithdraw(address _ibToken, uint256 _amount) external {}

  /// @notice Borrow a token agaist the placed collaterals on behlaf of the caller
  /// @param _subAccountId An index to derive the subaccount
  /// @param _token The token to borrow
  /// @param _amount The amount to borrow
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

  /// @notice Repay the debt for the subaccount
  /// @param _account The account to repay for
  /// @param _subAccountId An index to derive the subaccount
  /// @param _token The token to repay
  /// @param _debtShareToRepay The share amount of debt token to repay
  function repay(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _repayAmount,
    uint256 _debtShareToRepay
  ) external {
    // cache the balance of token before proceeding
    uint256 _amountBefore = IERC20(_token).balanceOf(address(this));

    // Fund this contract from caller
    // ignore the fact that there might be fee on transfer
    IERC20(_token).safeTransferFrom(msg.sender, address(this), _repayAmount);

    // Call repay by forwarding input _debtShareToRepay
    // Money Market should deduct the fund as much as possible
    // If there's excess amount left, transfer back to user
    IERC20(_token).safeApprove(moneyMarketDiamond, _repayAmount);
    IBorrowFacet(moneyMarketDiamond).repay(_account, _subAccountId, _token, _debtShareToRepay);
    IERC20(_token).safeApprove(moneyMarketDiamond, 0);

    // Calculate the excess amount left in the contract
    // This will revert if the input repay amount has lower value than _debtShareToRepay
    // And there's some token left in contract (can be done by inject token directly to this contract)
    uint256 _excessAmount = IERC20(_token).balanceOf(address(this)) - _amountBefore;

    if (_excessAmount != 0) {
      IERC20(_token).safeTransfer(msg.sender, _excessAmount);
    }
  }

  /// @notice Repay the debt for the subaccount using the same token on behalf of the caller
  /// @param _subAccountId An index to derive the subaccount
  /// @param _token The token to repay
  /// @param _debtShareToRepay The amount to repay
  function repayWithCollat(
    uint256 _subAccountId,
    address _token,
    uint256 _debtShareToRepay
  ) external {
    // Simply forward the call to MoneyMarket
    IBorrowFacet(moneyMarketDiamond).repayWithCollat(msg.sender, _subAccountId, _token, _debtShareToRepay);
  }

  function _deposit(address _token, uint256 _amount) internal returns (address _ibToken, uint256 _ibAmountReceived) {
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
    _ibAmountReceived = IERC20(_ibToken).balanceOf(address(this)) - _ibBalanceBeforeDeposit;
  }

  function _withdraw(address _ibToken, uint256 _shareAmount)
    internal
    returns (address _underlyingToken, uint256 _underlyingAmountReceived)
  {
    _underlyingToken = IViewFacet(moneyMarketDiamond).getTokenFromIbToken(_ibToken);
    // cache the balanceOf before executing withdrawal
    // This will be used to determine the actual amount of underlying token back from MoneyMarket
    // if the input ibToken is not ERC20, this call should revert at this point
    uint256 _underlyingTokenAmountBefore = IERC20(_underlyingToken).balanceOf(address(this));

    // Exchange the ibToken back to the underlying token with some interest
    // specifying to MoneyMarket that this withdraw is done on behalf of the caller
    // ibToken will be burned during the process
    ILendFacet(moneyMarketDiamond).withdraw(msg.sender, _ibToken, _shareAmount);

    // Calculate the actual amount received by comparing balance after - balance before
    // This is to accurately find the amount received even if the underlying token has fee on transfer
    _underlyingAmountReceived = IERC20(_underlyingToken).balanceOf(address(this)) - _underlyingTokenAmountBefore;
  }

  function _removeCollateral(
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) internal returns (uint256 _collateralAmountReceived) {
    // cache the balanceOf before executing remove collateral
    // This will be used to determine the actual amount of token back from MoneyMarket
    // if the input token is not ERC20, this call should revert at this point
    uint256 _tokenBalanceBefore = IERC20(_token).balanceOf(address(this));

    // Remove collateral from the subaccount on behalf of user
    // Will be reverted if removing collateral will violate the business rules based on
    // how MoneyMarket was configured
    ICollateralFacet(moneyMarketDiamond).removeCollateral(msg.sender, _subAccountId, _token, _amount);

    // Calculate the actual amount received by comparing balance after - balance before
    // This is to accurately find the amount received even if the underlying token has fee on transfer
    _collateralAmountReceived = IERC20(_token).balanceOf(address(this)) - _tokenBalanceBefore;
  }
}
