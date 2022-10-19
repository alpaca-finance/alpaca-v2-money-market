// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IDepositFacet {
  function deposit(address _token, uint256 _amount) external;

  error DepositFacet_InvalidToken(address _token);
}
