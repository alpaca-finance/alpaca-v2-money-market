// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { MiniFL_BaseTest } from "./MiniFL_BaseTest.t.sol";

// interfaces
import { IMiniFL } from "../../contracts/miniFL/interfaces/IMiniFL.sol";
import { IRewarder } from "../../contracts/miniFL/interfaces/IRewarder.sol";

contract MiniFL_Deposit is MiniFL_BaseTest {
  function setUp() public override {
    super.setUp();
    setupMiniFLPool();
  }

  function testRevert_WhenDepositMiniFLButPoolIsNotExists() external {
    vm.startPrank(ALICE);
    vm.expectRevert();
    miniFL.deposit(ALICE, notExistsPoolID, 10 ether);
    vm.stopPrank();
  }

  // #deposit ibToken (not debt token)
  function testCorrectness_WhenDepositMiniFLShouldWork() external {
    uint256 _aliceWethBalanceBefore = weth.balanceOf(ALICE);
    vm.startPrank(ALICE);
    weth.approve(address(miniFL), 10 ether);
    miniFL.deposit(ALICE, wethPoolID, 10 ether);
    vm.stopPrank();

    // transfer correctly
    assertEq(_aliceWethBalanceBefore - weth.balanceOf(ALICE), 10 ether);
    // check staking amount for ALICE as funder
    assertFunderAmount(ALICE, ALICE, wethPoolID, 10 ether);
    // check total staking amount
    assertTotalStakingAmount(ALICE, wethPoolID, 10 ether);
  }

  function testCorrectness_WhenOneFunderDepositMiniFLForAlice() external {
    uint256 _aliceWethBalanceBefore = weth.balanceOf(ALICE);
    uint256 _funder1WethBalanceBefore = weth.balanceOf(funder1);
    // funder1 deposit for ALICE
    vm.prank(funder1);
    miniFL.deposit(ALICE, wethPoolID, 10 ether);

    // ALICE balance should not changed
    assertEq(_aliceWethBalanceBefore - weth.balanceOf(ALICE), 0);
    assertEq(_funder1WethBalanceBefore - weth.balanceOf(funder1), 10 ether);

    // check staking amount per funder
    assertFunderAmount(ALICE, ALICE, wethPoolID, 0 ether);
    assertFunderAmount(funder1, ALICE, wethPoolID, 10 ether);

    // check total staking amount
    assertTotalStakingAmount(ALICE, wethPoolID, 10 ether);
  }

  function testCorrectness_WhenManyFunderDepositMiniFLForAlice() external {
    uint256 _aliceWethBalanceBefore = weth.balanceOf(ALICE);
    uint256 _funder1WethBalanceBefore = weth.balanceOf(funder1);
    uint256 _funder2WethBalanceBefore = weth.balanceOf(funder2);
    // funder1 deposit for ALICE
    vm.prank(funder1);
    miniFL.deposit(ALICE, wethPoolID, 10 ether);

    // funder2 deposit for ALICE
    vm.prank(funder2);
    miniFL.deposit(ALICE, wethPoolID, 11 ether);

    // ALICE balance should not changed
    assertEq(_aliceWethBalanceBefore - weth.balanceOf(ALICE), 0);
    assertEq(_funder1WethBalanceBefore - weth.balanceOf(funder1), 10 ether);
    assertEq(_funder2WethBalanceBefore - weth.balanceOf(funder2), 11 ether);

    // check staking amount per funder
    assertFunderAmount(ALICE, ALICE, wethPoolID, 0 ether);
    assertFunderAmount(funder1, ALICE, wethPoolID, 10 ether);
    assertFunderAmount(funder2, ALICE, wethPoolID, 11 ether);

    // check total staking amount for ALICE
    assertTotalStakingAmount(ALICE, wethPoolID, 21 ether);
  }

  // #deposit debtToken
  function testCorrectness_WhenDepositMiniFLDebtToken() external {
    uint256 _bobDebtTokenBalanceBefore = debtToken1.balanceOf(BOB);

    vm.startPrank(BOB);
    debtToken1.approve(address(miniFL), 10 ether);
    miniFL.deposit(BOB, dtokenPoolID, 10 ether);
    vm.stopPrank();

    assertEq(_bobDebtTokenBalanceBefore - debtToken1.balanceOf(BOB), 10 ether);
    // check staking amount for BOB as funder
    assertFunderAmount(BOB, BOB, dtokenPoolID, 10 ether);
    // check total staking amount
    assertTotalStakingAmount(BOB, dtokenPoolID, 10 ether);
  }

  // note: now debt token can deposit for another
  function testCorrectness_WhenDepositMiniFLWithDebtTokenForAnother() external {
    uint256 _bobDebtTokenBalanceBefore = debtToken1.balanceOf(BOB);
    // BOB deposit for ALICE
    vm.startPrank(BOB);
    debtToken1.approve(address(miniFL), 10 ether);
    miniFL.deposit(ALICE, dtokenPoolID, 10 ether);
    vm.stopPrank();

    assertEq(_bobDebtTokenBalanceBefore - debtToken1.balanceOf(BOB), 10 ether);

    // check staking amount for BOB as funder of ALICE
    assertFunderAmount(BOB, ALICE, dtokenPoolID, 10 ether);

    // check total staking amount
    assertTotalStakingAmount(BOB, dtokenPoolID, 0);
    assertTotalStakingAmount(ALICE, dtokenPoolID, 10 ether);
  }

  function testRevert_WhenNotAllowToDepositDebtToken() external {
    // alice is not debt token staker
    vm.expectRevert(abi.encodeWithSelector(IMiniFL.MiniFL_Forbidden.selector));
    vm.prank(ALICE);
    miniFL.deposit(BOB, dtokenPoolID, 10 ether);
  }
}
