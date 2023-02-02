// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { MiniFL_BaseTest } from "./MiniFL_BaseTest.t.sol";

// libs
import { LibAccount } from "../libs/LibAccount.sol";

// interfaces
import { IMiniFL } from "../../contracts/miniFL/interfaces/IMiniFL.sol";

contract MiniFL_EmergencyWithdrawWithRewarder is MiniFL_BaseTest {
  using LibAccount for address;

  function setUp() public override {
    super.setUp();
    setupMiniFLPool();
    setupRewarder();
  }

  function testCorrectness_WhenEmergencyWithdraw_ShouldCleanAllRewardersUserInfo() external {
    uint256 _depositedAmount = 10 ether;
    // alice deposited
    vm.startPrank(ALICE);
    weth.approve(address(miniFL), _depositedAmount);
    miniFL.deposit(ALICE, wethPoolID, _depositedAmount);
    vm.stopPrank();

    // bob deposited
    vm.startPrank(BOB);
    weth.approve(address(miniFL), _depositedAmount);
    miniFL.deposit(BOB, wethPoolID, _depositedAmount);
    vm.stopPrank();

    uint256 _aliceWethBalanceBefore = weth.balanceOf(ALICE);

    vm.startPrank(ALICE);
    miniFL.emergencyWithdraw(wethPoolID);
    vm.stopPrank();

    assertUserInfo(ALICE, wethPoolID, 0, 0);
    assertRewarderUserInfo(rewarder1, ALICE, wethPoolID, 0, 0);
    assertRewarderUserInfo(rewarder2, ALICE, wethPoolID, 0, 0);

    assertEq(ALICE.myBalanceOf(address(weth)) - _aliceWethBalanceBefore, _depositedAmount);

    // BOB should not effect
    assertUserInfo(BOB, wethPoolID, 10 ether, 0);
    assertRewarderUserInfo(rewarder1, BOB, wethPoolID, 10 ether, 0);
    assertRewarderUserInfo(rewarder2, BOB, wethPoolID, 10 ether, 0);
  }
}
