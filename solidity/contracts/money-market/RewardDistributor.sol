// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// interfaces
import { IRewardDistributor } from "./interfaces/IRewardDistributor.sol";

contract RewardDistributor is IRewardDistributor {
  using SafeERC20 for ERC20;

  function safeTransferReward(
    address _token,
    address _to,
    uint256 _amount
  ) external {
    ERC20 _rewardToken = ERC20(_token);
    if (_rewardToken.balanceOf(address(this)) < _amount) revert RewardDistributor_InsufficientBalance(_token, _amount);
    _rewardToken.safeTransfer(_to, _amount);
  }
}
