// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IRewardDistributor {
  function safeTransferReward(
    address _token,
    address _to,
    uint256 _amount
  ) external;

  // events
  event LogSafeTransferReward(address indexed _token, address _from, address _to, uint256 _amount);

  // errors
  error RewardDistributor_InsufficientBalance(address _token, uint256 _amount);
  error RewardDistributor_Unauthorized(address _caller);
}
