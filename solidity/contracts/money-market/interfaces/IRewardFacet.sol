// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";

interface IRewardFacet {
  function claimReward(address _token) external;

  function claimBorrowingRewardFor(address _to, address _token) external;

  function pendingLendingReward(address _account, address _token) external view returns (uint256);

  function pendingBorrowingReward(address _account, address _token) external view returns (uint256);

  function lenderRewardDebts(address _account, address _token) external view returns (int256);

  function borrowerRewardDebts(address _account, address _token) external view returns (int256);

  function getLendingPool(address _token) external view returns (LibMoneyMarket01.PoolInfo memory);

  function getBorrowingPool(address _token) external view returns (LibMoneyMarket01.PoolInfo memory);

  // errors
  error RewardFacet_InvalidAddress();
  error RewardFacet_InvalidRewardDistributor();
}
