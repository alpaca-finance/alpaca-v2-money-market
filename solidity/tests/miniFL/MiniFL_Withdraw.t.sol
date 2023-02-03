// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { MiniFL_BaseTest } from "./MiniFL_BaseTest.t.sol";

import { stdError } from "../utils/StdError.sol";

// interfaces
import { IMiniFL } from "../../contracts/miniFL/interfaces/IMiniFL.sol";

contract MiniFL_Withdraw is MiniFL_BaseTest {
  function setUp() public override {
    super.setUp();
    setupMiniFLPool();
  }

  // #withdraw ibToken (not debt token)
  function testCorrectness_WhenWithdrawAmountThatCoveredByBalance() external {
    // alice deposited
    vm.startPrank(ALICE);
    weth.approve(address(miniFL), 10 ether);
    miniFL.deposit(ALICE, wethPoolID, 10 ether);
    vm.stopPrank();

    uint256 _aliceWethBalanceBefore = weth.balanceOf(ALICE);

    vm.prank(ALICE);
    miniFL.withdraw(ALICE, wethPoolID, 5 ether);

    assertEq(weth.balanceOf(ALICE) - _aliceWethBalanceBefore, 5 ether);
  }

  function testRevert_WhenAliceWithdrawFromAmountOfFunder() external {
    // funder deposit for alice
    vm.prank(funder1);
    miniFL.deposit(ALICE, wethPoolID, 15 ether);

    // fund of funder must withdraw by funder
    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(IMiniFL.MiniFL_InsufficientAmount.selector));
    miniFL.withdraw(ALICE, wethPoolID, 10 ether);
  }

  function testRevert_WhenCallerWithdrawWithExceedAmount() external {
    // alice deposited
    vm.startPrank(ALICE);
    weth.approve(address(miniFL), 10 ether);
    miniFL.deposit(ALICE, wethPoolID, 10 ether);
    vm.stopPrank();

    // funder deposit for alice
    vm.prank(funder1);
    miniFL.deposit(ALICE, wethPoolID, 15 ether);

    vm.prank(funder2);
    miniFL.deposit(ALICE, wethPoolID, 20 ether);

    // alice could not withdraw more than 10
    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(IMiniFL.MiniFL_InsufficientAmount.selector));
    miniFL.withdraw(ALICE, wethPoolID, 11 ether);

    // funder1 could not withdraw more than 15
    vm.prank(funder1);
    vm.expectRevert(abi.encodeWithSelector(IMiniFL.MiniFL_InsufficientAmount.selector));
    miniFL.withdraw(ALICE, wethPoolID, 16 ether);

    // funder2 could not withdraw more than 20
    vm.prank(funder2);
    vm.expectRevert(abi.encodeWithSelector(IMiniFL.MiniFL_InsufficientAmount.selector));
    miniFL.withdraw(ALICE, wethPoolID, 20.1 ether);
  }

  // #withdraw debtToken
  function testCorrectness_WhenWithdrawDebtToken() external {
    // bob deposit on debt token
    vm.startPrank(BOB);
    debtToken1.approve(address(miniFL), 10 ether);
    miniFL.deposit(BOB, dtokenPoolID, 10 ether);
    vm.stopPrank();

    uint256 _bobDTokenBalanceBefore = debtToken1.balanceOf(BOB);

    vm.prank(BOB);
    miniFL.withdraw(BOB, dtokenPoolID, 5 ether);

    assertEq(debtToken1.balanceOf(BOB) - _bobDTokenBalanceBefore, 5 ether);
  }

  // staker can withdraw for another
  function testCorrectness_WhenWithdrawDebtTokenForAnother() external {
    // bob deposit on debt token for ALICE
    vm.startPrank(BOB);
    debtToken1.approve(address(miniFL), 10 ether);
    miniFL.deposit(ALICE, dtokenPoolID, 10 ether);
    vm.stopPrank();

    uint256 _bobDTokenBalanceBefore = debtToken1.balanceOf(BOB);

    // bob withdraw on debt token for ALICE
    vm.prank(BOB);
    miniFL.withdraw(ALICE, dtokenPoolID, 5 ether);

    assertEq(debtToken1.balanceOf(BOB) - _bobDTokenBalanceBefore, 5 ether);
    // need to check pending alpaca ??????
  }

  function testRevert_WhenNotAllowToWithdrawDebtToken() external {
    vm.expectRevert(abi.encodeWithSelector(IMiniFL.MiniFL_Forbidden.selector));
    vm.prank(ALICE);
    miniFL.withdraw(ALICE, dtokenPoolID, 5 ether);
  }
}
