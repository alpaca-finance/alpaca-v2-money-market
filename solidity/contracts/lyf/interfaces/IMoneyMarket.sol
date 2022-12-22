// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IMoneyMarket {
  function tokenToIbTokens(address _token) external view returns (address);

  function ibTokenToTokens(address _ibToken) external view returns (address);

  function nonCollatBorrow(address _token, uint256 _amount) external;

  function getGlobalDebt(address _token) external view returns (uint256, uint256);

  function getFloatingBalance(address _token) external view returns (uint256);

  function getNonCollatAccountDebt(address _account, address _token) external view returns (uint256 _debtAmount);

  function withdraw(address _ibToken, uint256 _shareAmount) external returns (uint256 _shareValue);

  function deposit(address _token, uint256 _amount) external;

  function getIbShareFromUnderlyingAmount(address _token, uint256 _underlyingAmount)
    external
    view
    returns (uint256 _ibShareAmount);

  function getTotalToken(address _token) external view returns (uint256);

  function getTotalTokenWithPendingInterest(address _token) external view returns (uint256 _totalToken);
}
