// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";

import { console } from "../utils/console.sol";

contract MoneyMarket_RewardTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();

    // mint ib token for users
    ibWeth.mint(ALICE, 10 ether);
  }

  function testCorrectness_WhenUserAddCollateralAndClaimReward_UserShouldReceivedRewardCorrectly() external {
    address _ibToken = address(ibWeth);
    vm.startPrank(ALICE);
    ibWeth.approve(moneyMarketDiamond, 10 ether);
    collateralFacet.addCollateral(ALICE, 0, _ibToken, 10 ether);
    vm.stopPrank();

    assertEq(collateralFacet.accountIbTokenCollats(ALICE, _ibToken), 10 ether);
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether);
    vm.warp(block.timestamp + 100);

    uint256 _pendingReward = claimRewardFacet.pendingReward(ALICE, _ibToken);

    vm.prank(ALICE);
    claimRewardFacet.claimReward(_ibToken);

    assertEq(claimRewardFacet.accountRewardDebts(ALICE, _ibToken), _pendingReward);
    assertEq(rewardToken.balanceOf(ALICE), _pendingReward);
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether - _pendingReward);
  }

  function testCorrectness_WhenUserAddCollateralAndRemoveCollat_UserShouldReceivedRewardCorrectly() external {
    address _ibToken = address(ibWeth);
    vm.startPrank(ALICE);
    ibWeth.approve(moneyMarketDiamond, 10 ether);
    collateralFacet.addCollateral(ALICE, 0, _ibToken, 10 ether);
    vm.stopPrank();

    assertEq(collateralFacet.accountIbTokenCollats(ALICE, _ibToken), 10 ether);
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether);
    vm.warp(block.timestamp + 100);

    uint256 _pendingReward = claimRewardFacet.pendingReward(ALICE, _ibToken);

    vm.prank(ALICE);
    collateralFacet.removeCollateral(0, _ibToken, 10 ether);

    // assertEq(claimRewardFacet.accountRewardDebts(ALICE, _ibToken), 0 ether);
    // assertEq(rewardToken.balanceOf(ALICE), _pendingReward);
    // assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether - _pendingReward);
  }
}
