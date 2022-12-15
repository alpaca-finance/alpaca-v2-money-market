// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { AV_BaseTest, console } from "./AV_BaseTest.t.sol";

contract AV_TradeFacetTest is AV_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenDepositToken_ShouldWork() external {
    vm.prank(ALICE);
    tradeFacet.deposit(address(avShareToken), 1 ether, 0);
  }

  function testCorrectness_WhenWithdrawToken_ShouldWork() external {
    vm.startPrank(ALICE);
    tradeFacet.deposit(address(avShareToken), 1 ether, 0);
    tradeFacet.withdraw(address(avShareToken), 1 ether, 0);
    vm.stopPrank();
  }
}
