// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface IAVHandler {
  function onDeposit(
    address _depositFrom,
    address _token,
    uint256 _amount
  ) external returns (uint256);
}
