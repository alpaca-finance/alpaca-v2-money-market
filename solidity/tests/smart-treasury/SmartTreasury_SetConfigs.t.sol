// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseFork, console } from "./BaseFork.sol";

contract SmartTreasury_SetConfigs is BaseFork {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_SetWhitelist_ShouldWork() external {
    address[] memory _callers = new address[](2);
    _callers[0] = ALICE;
    _callers[1] = BOB;
    vm.prank(DEPLOYER);
    smartTreasury.setWhitelistedCallers(_callers, true);

    assertEq(smartTreasury.whitelistedCallers(ALICE), true);
    assertEq(smartTreasury.whitelistedCallers(BOB), true);
  }

  function testRevert_NonOwnerSetWhitelist_ShouldRevert() external {}

  // test set whitelist
  // - by deployer
  // - by unauthorized user

  function testCorrectness_SetRevenueToken_ShouldWork() external {}

  function testRevert_UnauthorizedCallerSetRevenueToken_ShouldRevert() external {}

  // test correctness revenue token
  // - by whitelisted user
  // - by unauthorized user

  function testCorrectness_SetAlloc_ShouldWork() external {}

  function testRevert_UnauthorizedCallerSetAlloc_ShouldRevert() external {}

  // test correctness allocation point
  // - by whitelisted user
  // - by unauthorized user
}
