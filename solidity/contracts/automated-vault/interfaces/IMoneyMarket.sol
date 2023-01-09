// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface IMoneyMarket {
  function getIbTokenFromToken(address _token) external view returns (address);

  function getTokenFromIbToken(address _ibToken) external view returns (address);

  function nonCollatBorrow(address _token, uint256 _amount) external;

  function nonCollatRepay(
    address _account,
    address _token,
    uint256 _repayAmount
  ) external;

  function getGlobalDebt(address _token) external view returns (uint256, uint256);

  function getDebtForLpToken(address _token) external view returns (uint256, uint256);

  function getFloatingBalance(address _token) external view returns (uint256);

  function nonCollatGetDebt(address _account, address _token) external view returns (uint256 _debtAmount);

  function withdraw(address _ibToken, uint256 _shareAmount) external returns (uint256 _shareValue);

  function deposit(address _token, uint256 _amount) external;

  function getIbShareFromUnderlyingAmount(address _token, uint256 _underlyingAmount)
    external
    view
    returns (uint256 _ibShareAmount);
}
