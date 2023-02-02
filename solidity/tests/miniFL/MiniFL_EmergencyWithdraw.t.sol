// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { MiniFL_BaseTest } from "./MiniFL_BaseTest.t.sol";

// interfaces
import { IMiniFL } from "../../contracts/miniFL/interfaces/IMiniFL.sol";

contract MiniFL_EmergencyWithdraw is MiniFL_BaseTest {
  function setUp() public override {
    super.setUp();
    setupMiniFLPool();
  }

  function testCorrectness_WhenEmergencyWithdraw() external {
    uint256 _depositedAmount = 10 ether;
    // alice deposited
    vm.startPrank(ALICE);
    weth.approve(address(miniFL), _depositedAmount);
    miniFL.deposit(ALICE, wethPoolID, _depositedAmount);
    vm.stopPrank();

    uint256 _aliceWethBalanceBefore = weth.balanceOf(ALICE);

    vm.prank(ALICE);
    miniFL.emergencyWithdraw(wethPoolID);

    assertUserInfo(ALICE, wethPoolID, 0, 0);
    assertEq(weth.balanceOf(ALICE) - _aliceWethBalanceBefore, _depositedAmount);
  }

  function testRevert_WhenEmergencyWithdrawDebtToken() external {
    // alice deposited
    vm.startPrank(BOB);
    debtToken1.approve(address(miniFL), 10 ether);
    miniFL.deposit(BOB, dtokenPoolID, 10 ether);

    vm.expectRevert(abi.encodeWithSelector(IMiniFL.MiniFL_Forbidden.selector));
    miniFL.emergencyWithdraw(dtokenPoolID);

    vm.stopPrank();
  }
}
