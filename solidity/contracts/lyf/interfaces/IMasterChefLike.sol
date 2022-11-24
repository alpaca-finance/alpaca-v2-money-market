// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface IMasterChefLike {
  function deposit(uint256 pid, uint256 amount) external;

  function withdraw(uint256 pid, uint256 amount) external;
}
