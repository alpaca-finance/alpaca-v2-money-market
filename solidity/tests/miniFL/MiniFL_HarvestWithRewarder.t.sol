// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { MiniFL_BaseTest } from "./MiniFL_BaseTest.t.sol";

// libs
import { LibAccount } from "../libs/LibAccount.sol";

// interfaces
import { IMiniFL } from "../../contracts/miniFL/interfaces/IMiniFL.sol";

contract MiniFL_HarvestWithRewarder is MiniFL_BaseTest {
  using LibAccount for address;

  uint256 _aliceTotalWethDeposited = 20 ether;
  uint256 _aliceDTokenDeposited = 10 ether;

  uint256 _bobTotalWethDeposited = 10 ether;
  uint256 _bobDTokenDeposited = 90 ether;

  function setUp() public override {
    super.setUp();
    setupMiniFLPool();
    setupRewarder();

    prepareForHarvest();

    // deposited info
    // --------------------------------------
    // | Pool                 | ALICE | BOB |
    // |----------------------|-------|-----|
    // | WETH                 |    20 |  10 |
    // | DToken               |    10 |  90 |
    // | WETH (rewarder1)     |    20 |  10 |
    // | DToken (rewarder 1)  |    10 |  90 |
    // | WETH (rewarder 2)    |    20 |  10 |
    // | DToken (rewarder 2)  |     0 |   0 | NOTE: because rewarder 2 is not register to DToken Pool
    // --------------------------------------
  }

  function testCorrectness_WhenTimepast_AndHarvest_GotAllReward() external {
    // timpast for 100 second
    vm.warp(block.timestamp + 100);

    // assets before
    uint256 _aliceAlpacaBefore = ALICE.myBalanceOf(address(alpaca));
    uint256 _aliceReward1Before = ALICE.myBalanceOf(address(rewardToken1));
    uint256 _aliceReward2Before = ALICE.myBalanceOf(address(rewardToken2));

    uint256 _bobAlpacaBefore = BOB.myBalanceOf(address(alpaca));
    uint256 _bobReward1Before = BOB.myBalanceOf(address(rewardToken1));
    uint256 _bobReward2Before = BOB.myBalanceOf(address(rewardToken2));

    // note: ref pending reward from MiniFL_PendingRewardWithRewarder.sol:testCorrectness_WhenTimpast_RewarderPendingTokenShouldBeCorrectly
    // ALICE Reward
    // --------------------------------------------------------------
    // |    Pool |  ALPACA Reward | Reward Token 1 | Reward Token 2 |
    // |---------|----------------|----------------|----------------|
    // |    WETH |          40000 |           6000 |          10000 |
    // |  DToken |           4000 |            100 |              0 |
    // |   Total |          44000 |           6100 |          10000 |
    // --------------------------------------------------------------
    vm.prank(ALICE);
    miniFL.harvest(wethPoolID);
    assertTotalStakingAmountWithReward(ALICE, wethPoolID, _aliceTotalWethDeposited, 40000 ether);
    assertRewarderUserInfo(rewarder1, ALICE, wethPoolID, _aliceTotalWethDeposited, 6000 ether);
    assertRewarderUserInfo(rewarder2, ALICE, wethPoolID, _aliceTotalWethDeposited, 10000 ether);

    vm.prank(ALICE);
    miniFL.harvest(dtokenPoolID);
    assertTotalStakingAmountWithReward(ALICE, dtokenPoolID, _aliceDTokenDeposited, 4000 ether);
    assertRewarderUserInfo(rewarder1, ALICE, dtokenPoolID, _aliceDTokenDeposited, 100 ether);
    assertRewarderUserInfo(rewarder2, ALICE, dtokenPoolID, 0, 0);

    assertEq(ALICE.myBalanceOf(address(alpaca)) - _aliceAlpacaBefore, 44000 ether);
    assertEq(ALICE.myBalanceOf(address(rewardToken1)) - _aliceReward1Before, 6100 ether);
    assertEq(ALICE.myBalanceOf(address(rewardToken2)) - _aliceReward2Before, 10000 ether);

    // BOB Reward
    // --------------------------------------------------------------
    // |    Pool |  ALPACA Reward | Reward Token 1 | Reward Token 2 |
    // |---------|----------------|----------------|----------------|
    // |    WETH |          20000 |           3000 |           5000 |
    // |  DToken |          36000 |            900 |              0 |
    // |   Total |          56000 |           3900 |           5000 |
    // --------------------------------------------------------------
    vm.prank(BOB);
    miniFL.harvest(wethPoolID);
    assertTotalStakingAmountWithReward(BOB, wethPoolID, _bobTotalWethDeposited, 20000 ether);
    assertRewarderUserInfo(rewarder1, BOB, wethPoolID, _bobTotalWethDeposited, 3000 ether);
    assertRewarderUserInfo(rewarder2, BOB, wethPoolID, _bobTotalWethDeposited, 5000 ether);

    vm.prank(BOB);
    miniFL.harvest(dtokenPoolID);
    assertTotalStakingAmountWithReward(BOB, dtokenPoolID, _bobDTokenDeposited, 36000 ether);
    assertRewarderUserInfo(rewarder1, BOB, dtokenPoolID, _bobDTokenDeposited, 900 ether);
    assertRewarderUserInfo(rewarder2, BOB, dtokenPoolID, 0, 0);

    assertEq(BOB.myBalanceOf(address(alpaca)) - _bobAlpacaBefore, 56000 ether);
    assertEq(BOB.myBalanceOf(address(rewardToken1)) - _bobReward1Before, 3900 ether);
    assertEq(BOB.myBalanceOf(address(rewardToken2)) - _bobReward2Before, 5000 ether);
  }

  function testRevert_Rewarder1IsNotEnoughForHarvest() external {
    vm.warp(block.timestamp + 100);
    // burned all token in rewarder1
    address _reward = address(rewarder1);
    rewardToken1.burn(_reward, _reward.myBalanceOf(address(rewardToken1)));

    // should revert when rewarder try transfer reward to ALICE
    vm.expectRevert();
    vm.prank(ALICE);
    miniFL.harvest(wethPoolID);
  }
}
