// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface IMoneyMarketAccountManager {
  error MoneyMarketAccountManager_WNativeMarketNotOpen();
  error MoneyMarketAccountManager_InvalidAmount();

  function deposit(address _token, uint256 _amount) external;

  function depositETH() external payable;

  function withdraw(address _ibToken, uint256 _ibAmount) external;

  function withdrawETH(uint256 _ibAmount) external;

  function addCollateralFor(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external;

  function removeCollateral(
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external;

  function transferCollateral(
    uint256 _fromSubAccountId,
    uint256 _toSubAccountId,
    address _token,
    uint256 _amount
  ) external;

  function depositAndAddCollateral(
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external;

  function depositETHAndAddCollateral(uint256 _subAccountId) external payable;

  function removeCollateralAndWithdraw(
    uint256 _subAccountId,
    address _ibToken,
    uint256 _ibAmount
  ) external;

  function removeCollateralAndWithdrawETH(uint256 _subAccountId, uint256 _amount) external;

  function depositAndStake(address _token, uint256 _amount) external;

  function unstakeAndWithdraw(address _ibToken, uint256 _amount) external;

  function borrow(
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external;

  function borrowETH(uint256 _subAccountId, uint256 _amount) external;

  function repayFor(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _repayAmount,
    uint256 _debtShareToRepay
  ) external;

  function repayETHFor(
    address _account,
    uint256 _subAccountId,
    uint256 _debtShareToRepay
  ) external payable;

  function repayWithCollat(
    uint256 _subAccountId,
    address _token,
    uint256 _debtShareAmount
  ) external;
}
