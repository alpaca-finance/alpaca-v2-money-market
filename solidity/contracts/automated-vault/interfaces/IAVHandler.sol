// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface IAVHandler {
  function totalLpBalance() external view returns (uint256);
}
