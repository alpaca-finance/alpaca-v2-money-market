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

  uint256 _aliceWethDeposited = 20 ether;
  uint256 _aliceDTokenDeposited = 10 ether;

  uint256 _bobWethDeposited = 10 ether;
  uint256 _bobDTokenDeposited = 90 ether;

  function setUp() public override {
    super.setUp();
    setupMiniFLPool();
    prepareForHarvest();

    // deposited info
    // ------------------------
    // | Pool   | ALICE | BOB |
    // |--------|-------|-----|
    // | WETH   |    20 |  10 |
    // | DToken |    10 |  90 |
    // ------------------------
  }

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

    // alice pending alpaca on WETHPool = 40000
    vm.prank(ALICE);
    miniFL.harvest(wethPoolID);
    assertUserInfo(ALICE, wethPoolID, _aliceWethDeposited, 40000 ether);

    // alice pending alpaca on DTOKENPool = 4000
    vm.prank(ALICE);
    miniFL.harvest(dtokenPoolID);
    assertUserInfo(ALICE, dtokenPoolID, _aliceDTokenDeposited, 4000 ether);

    // bob pending alpaca on WETHPool = 20000
    vm.prank(BOB);
    miniFL.harvest(wethPoolID);
    assertUserInfo(BOB, wethPoolID, _bobWethDeposited, 20000 ether);

    // bob pending alpaca on DTOKENPool = 36000
    vm.prank(BOB);
    miniFL.harvest(dtokenPoolID);
    assertUserInfo(BOB, dtokenPoolID, _bobDTokenDeposited, 36000 ether);

    // assert all alpaca received
    assertEq(ALICE.myBalanceOf(address(alpaca)) - _aliceAlpacaBefore, 44000 ether);
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
