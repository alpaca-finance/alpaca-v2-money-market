// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseFork } from "./BaseFork.sol";
import { ISmartTreasury } from "solidity/contracts/interfaces/ISmartTreasury.sol";

contract SmartTreasury_SetConfigs is BaseFork {
  function setUp() public override {
    super.setUp();
  }

  // test set whitelist
  // - called by deployer
  // - called by unauthorized user

  function testCorrectness_SetWhitelist_ShouldWork() external {
    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;
    vm.prank(DEPLOYER);
    smartTreasury.setWhitelistedCallers(_callers, true);

    assertEq(smartTreasury.whitelistedCallers(ALICE), true, "Set Whitelist");
  }

  function testRevert_NonOwnerSetWhitelist_ShouldRevert() external {
    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;
    vm.expectRevert("Ownable: caller is not the owner");
    smartTreasury.setWhitelistedCallers(_callers, true);
  }

  // test correctness revenue token
  // - called by whitelisted user
  // - called by unauthorized user

  function testCorrectness_SetRevenueToken_ShouldWork() external {
    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;
    vm.prank(DEPLOYER);
    smartTreasury.setWhitelistedCallers(_callers, true);

    vm.prank(ALICE);
    smartTreasury.setRevenueToken(address(wbnb));
    assertEq(smartTreasury.revenueToken(), address(wbnb), "Set Revenue Token");
  }

  function testRevert_UnauthorizedCallerSetRevenueToken_ShouldRevert() external {
    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;
    vm.prank(DEPLOYER);
    smartTreasury.setWhitelistedCallers(_callers, true);

    vm.prank(BOB);
    vm.expectRevert(ISmartTreasury.SmartTreasury_Unauthorized.selector);
    smartTreasury.setRevenueToken(address(wbnb));
  }

  // test correctness allocation point
  // - called by whitelisted user
  // - called by unauthorized user

  function testCorrectness_SetAlloc_ShouldWork() external {
    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;
    vm.prank(DEPLOYER);
    smartTreasury.setWhitelistedCallers(_callers, true);

    vm.prank(ALICE);
    smartTreasury.setAllocPoints(100, 100, 100);
    assertEq(smartTreasury.revenueAllocPoint(), 100, "Set Revenue Allocation");
    assertEq(smartTreasury.devAllocPoint(), 100, "Set Dev Allocation");
    assertEq(smartTreasury.burnAllocPoint(), 100, "Set Burn Allocation");
  }

  function testRevert_UnauthorizedCallerSetAlloc_ShouldRevert() external {
    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;
    vm.prank(DEPLOYER);
    smartTreasury.setWhitelistedCallers(_callers, true);

    vm.prank(BOB);
    vm.expectRevert(ISmartTreasury.SmartTreasury_Unauthorized.selector);
    smartTreasury.setAllocPoints(100, 100, 100);
  }

  // test correctness treasury address
  // - called by whitelisted user
  // - called by unauthorized user

  function testCorrectness_SetTreasuryAddresses_ShouldWork() external {
    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;
    vm.prank(DEPLOYER);
    smartTreasury.setWhitelistedCallers(_callers, true);

    vm.prank(ALICE);
    smartTreasury.setTreasuryAddresses(REVENUE_TREASURY, DEV_TREASURY, BURN_TREASURY);
    assertEq(smartTreasury.revenueTreasury(), REVENUE_TREASURY, "Set Revenue treasury address");
    assertEq(smartTreasury.devTreasury(), DEV_TREASURY, "Set Dev treasury address");
    assertEq(smartTreasury.burnTreasury(), BURN_TREASURY, "Set Burn treasury address");
  }

  function testRevert_UnauthorizedCallerSetTreasuryAddresses_ShouldRevert() external {
    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;
    vm.prank(DEPLOYER);
    smartTreasury.setWhitelistedCallers(_callers, true);

    vm.prank(BOB);
    vm.expectRevert(ISmartTreasury.SmartTreasury_Unauthorized.selector);
    smartTreasury.setTreasuryAddresses(REVENUE_TREASURY, DEV_TREASURY, BURN_TREASURY);
  }
}
