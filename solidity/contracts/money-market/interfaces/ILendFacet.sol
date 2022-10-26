// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ILendFacet {
  function deposit(address _token, uint256 _amount) external;

  error LendFacet_InvalidToken(address _token);
}
