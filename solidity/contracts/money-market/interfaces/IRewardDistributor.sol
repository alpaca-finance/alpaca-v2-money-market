// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IRewardDistributor {
  function safeTransferReward(
    address _token,
    address _to,
    uint256 _amount
  ) external;

  // errors
  error RewardDistributor_InsufficientBalance(address _token, uint256 _amount);
}
