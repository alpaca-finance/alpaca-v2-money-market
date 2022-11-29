// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface IClaimRewardFacet {
  function claimReward(address _token) external;

  function pendingReward(address _token) external returns (uint256 _pendingReward);

  // errors
  error ClaimRewardFacet_InvalidAddress();
}
