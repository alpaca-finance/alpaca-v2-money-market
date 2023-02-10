// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IMiniFL {
  function poolLength() external view returns (uint256);

  function totalAllocPoint() external view returns (uint256);

  function addPool(
    uint256 _allocPoint,
    address _stakingToken,
    bool _withUpdate
  ) external;
}
