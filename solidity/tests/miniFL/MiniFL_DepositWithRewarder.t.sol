// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { MiniFL_BaseTest } from "./MiniFL_BaseTest.t.sol";

import { Rewarder } from "../../contracts/miniFL/Rewarder.sol";

// interfaces
import { IMiniFL } from "../../contracts/miniFL/interfaces/IMiniFL.sol";

contract MiniFL_DepositWithRewarder is MiniFL_BaseTest {
  function setUp() public override {
    super.setUp();
    setupMiniFLPool();
    setupRewarder();
  }

  function testCorrectness_WhenDeposit_RewarderUserInfoShouldBeCorrect() external {
    uint256 _aliceWethBalanceBefore = weth.balanceOf(ALICE);
    vm.startPrank(ALICE);
    weth.approve(address(miniFL), 10 ether);
    miniFL.deposit(ALICE, wethPoolID, 10 ether);
    vm.stopPrank();

    // assert alice balance
    assertEq(_aliceWethBalanceBefore - weth.balanceOf(ALICE), 10 ether);

    // assert reward user info, both user info should be same
    assertRewarderUserInfo(rewarder1, ALICE, wethPoolID, 10 ether, 0);
    assertRewarderUserInfo(rewarder2, ALICE, wethPoolID, 10 ether, 0);
  }

  function testCorrectness_WhenDepositDebtToken_RewarderUserInfoShouldBeCorrect() external {
    uint256 _bobDebtTokenBalanceBefore = debtToken1.balanceOf(BOB);

    vm.startPrank(BOB);
    debtToken1.approve(address(miniFL), 10 ether);
    miniFL.deposit(BOB, dtokenPoolID, 10 ether);
    vm.stopPrank();

    // assert bob balance
    assertEq(_bobDebtTokenBalanceBefore - debtToken1.balanceOf(BOB), 10 ether);

    // assert reward user info
    assertRewarderUserInfo(rewarder1, BOB, dtokenPoolID, 10 ether, 0);
    // rewarder2 is not register in this pool then user amount should be 0
    assertRewarderUserInfo(rewarder2, BOB, dtokenPoolID, 0, 0);
  }
}
