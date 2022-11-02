// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ILendFacet {
  function deposit(address _token, uint256 _amount) external;

  function withdraw(address _ibToken, uint256 _shareAmount) external;

  function getTotalToken(address _token) external view returns (uint256);

  function debtValues(address _token) external view returns (uint256);

  function debtShares(address _token) external view returns (uint256);

  error LendFacet_InvalidToken(address _token);
}
