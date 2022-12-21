// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { MiniFL_BaseTest } from "./MiniFL_BaseTest.t.sol";

// libs
import { LibAccount } from "../libs/LibAccount.sol";

// interfaces
import { IMiniFL } from "../../contracts/miniFL/interfaces/IMiniFL.sol";

contract MiniFL_Harvest is MiniFL_BaseTest {
  using LibAccount for address;

  function setUp() public override {
    super.setUp();
    prepareMiniFLPool();
    prepareForHarvest();
  }

  // note:
  // block timestamp start at 1
  // alpaca per second is 1000 ether
  // weth pool alloc point is 60%
  // dtoken pool alloc point is 40%

  function testCorrectness_WhenHarvestWithNoRewardPending() external {
    // alpaca is base reward
    uint256 _balanceBefore = ALICE.myBalanceOf(address(alpaca));

    vm.prank(ALICE);
    miniFL.harvest(wethPoolID);

    assertEq(_balanceBefore, ALICE.myBalanceOf(address(alpaca)));
  }

  function testCorrectness_WhenTimepast_AndHarvest() external {
    // timpast for 100 second
    vm.warp(block.timestamp + 100);
    uint256 _aliceAlpacaBefore = ALICE.myBalanceOf(address(alpaca));
    uint256 _bobAlpacaBefore = BOB.myBalanceOf(address(alpaca));

    // alice harvest all pools
    vm.startPrank(ALICE);
    miniFL.harvest(wethPoolID);
    miniFL.harvest(dtokenPoolID);
    vm.stopPrank();

    // bob harvest all pools
    vm.startPrank(BOB);
    miniFL.harvest(wethPoolID);
    miniFL.harvest(dtokenPoolID);
    vm.stopPrank();

    // note: ref pending alpaca from MiniFL_PendingAlpaca.sol:testCorrectness_WhenTimpast_PendingRewardShouldBeCorrectly
    // alice pending alpaca on WETHPool = 40000
    // alice pending alpaca on DTOKENPool = 4000
    assertEq(ALICE.myBalanceOf(address(alpaca)) - _aliceAlpacaBefore, 44000 ether);

    // bob pending alpaca on WETHPool = 20000
    // bob pending alpaca on DTOKENPool = 36000
    assertEq(BOB.myBalanceOf(address(alpaca)) - _bobAlpacaBefore, 56000 ether);
  }

  function testRevert_AlpacaIsNotEnoughForHarvest() external {
    // timepast too far, made alpaca distributed 1000000 * 1000 = 1000,000,000 but alpaca in miniFL has only 10,000,000
    vm.warp(block.timestamp + 1000000);

    vm.startPrank(ALICE);
    vm.expectRevert();
    miniFL.harvest(wethPoolID);
    vm.stopPrank();
  }
}
