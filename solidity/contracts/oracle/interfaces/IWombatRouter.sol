// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IWombatRouter {
  function getAmountOut(
    address[] calldata tokenPath,
    address[] calldata poolPath,
    int256 amountIn
  ) external view returns (uint256 amountOut, uint256[] memory haircuts);
}
