// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IMoneyMarket {
  function tokenToIbTokens(address _token) external view returns (address);

  function ibTokenToTokens(address _ibToken) external view returns (address);

  function nonCollatBorrow(address _token, uint256 _amount) external;

  function getGlobalDebt(address _token) external view returns (uint256, uint256);

  function getFloatingBalance(address _token) external view returns (uint256);
}
