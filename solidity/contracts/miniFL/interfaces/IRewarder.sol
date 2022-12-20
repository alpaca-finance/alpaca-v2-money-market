// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IRewarder {
  function name() external view returns (string memory);

  function onDeposit(
    uint256 pid,
    address user,
    uint256 alpacaAmount,
    uint256 newStakeTokenAmount
  ) external;

  function onWithdraw(
    uint256 pid,
    address user,
    uint256 alpacaAmount,
    uint256 newStakeTokenAmount
  ) external;

  function onHarvest(
    uint256 pid,
    address user,
    uint256 alpacaAmount
  ) external;

  function pendingTokens(
    uint256 pid,
    address user,
    uint256 alpacaAmount
  ) external view returns (IERC20Upgradeable[] memory, uint256[] memory);
}
