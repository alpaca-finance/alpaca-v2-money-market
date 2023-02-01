// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "./IRewarder.sol";

interface IMiniFL {
  error MiniFL_DuplicatePool();
  error MiniFL_Forbidden();
  error MiniFL_InvalidArguments();
  error MiniFL_BadRewarder();

  event LogDeposit(address indexed caller, address indexed user, uint256 indexed pid, uint256 amount);
  event LogWithdraw(address indexed caller, address indexed user, uint256 indexed pid, uint256 amount);
  event LogEmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
  event LogHarvest(address indexed user, uint256 indexed pid, uint256 amount);
  event LogAddPool(uint256 indexed pid, uint256 allocPoint, IERC20Upgradeable indexed stakingToken);
  event LogSetPool(uint256 indexed pid, uint256 allocPoint);
  event LogUpdatePool(uint256 indexed pid, uint64 lastRewardTime, uint256 stakedBalance, uint256 accAlpacaPerShare);
  event LogAlpacaPerSecond(uint256 alpacaPerSecond);
  event LogApproveStakeDebtToken(uint256 indexed _pid, address indexed _staker, bool allow);
  event LogSetMaxAlpacaPerSecond(uint256 maxAlpacaPerSecond);
  event LogSetPoolRewarder(uint256 indexed pid, address rewarder);

  function stakingToken(uint256 _pid) external view returns (IERC20Upgradeable);
}
