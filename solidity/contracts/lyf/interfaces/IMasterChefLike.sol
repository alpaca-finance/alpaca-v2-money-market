// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IMasterChefLike {
  function deposit(uint256 _pid, uint256 _amount) external;

  function withdraw(uint256 _pid, uint256 _amount) external;
}
