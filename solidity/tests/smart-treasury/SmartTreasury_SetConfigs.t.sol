// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseFork } from "./BaseFork.sol";
import { ISmartTreasury } from "solidity/contracts/interfaces/ISmartTreasury.sol";

contract SmartTreasury_SetConfigs is BaseFork {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_SetWhitelist_ShouldWork() external {
    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;
    vm.prank(DEPLOYER);
    smartTreasury.setWhitelistedCallers(_callers, true);

    assertEq(smartTreasury.whitelistedCallers(ALICE), true, "Set Whitelist");
  }

  function testCorrectness_SetRevenueToken_ShouldWork() external {
    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;
    vm.prank(DEPLOYER);
    smartTreasury.setWhitelistedCallers(_callers, true);

    vm.startPrank(ALICE);
    smartTreasury.setRevenueToken(address(wbnb));
    assertEq(smartTreasury.revenueToken(), address(wbnb), "Set Revenue Token");

    // evm revert, since it will try to call address.decimals() which not existing
    vm.expectRevert();
    smartTreasury.setRevenueToken(address(199));

    vm.stopPrank();
  }

  function testCorrectness_SetAlloc_ShouldWork() external {
    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;
    vm.prank(DEPLOYER);
    smartTreasury.setWhitelistedCallers(_callers, true);

    vm.startPrank(ALICE);
    smartTreasury.setAllocPoints(100, 100, 100);
    assertEq(smartTreasury.revenueAllocPoint(), 100, "Set Revenue Allocation");
    assertEq(smartTreasury.devAllocPoint(), 100, "Set Dev Allocation");
    assertEq(smartTreasury.burnAllocPoint(), 100, "Set Burn Allocation");

    vm.expectRevert(ISmartTreasury.SmartTreasury_InvalidAllocPoint.selector);
    smartTreasury.setAllocPoints(10001, 100, 100);
    vm.expectRevert(ISmartTreasury.SmartTreasury_InvalidAllocPoint.selector);
    smartTreasury.setAllocPoints(100, 10001, 100);
    vm.expectRevert(ISmartTreasury.SmartTreasury_InvalidAllocPoint.selector);
    smartTreasury.setAllocPoints(100, 100, 10001);

    vm.stopPrank();
  }

  function testCorrectness_SetTreasuryAddresses_ShouldWork() external {
    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;
    vm.prank(DEPLOYER);
    smartTreasury.setWhitelistedCallers(_callers, true);

    vm.startPrank(ALICE);
    smartTreasury.setTreasuryAddresses(REVENUE_TREASURY, DEV_TREASURY, BURN_TREASURY);
    assertEq(smartTreasury.revenueTreasury(), REVENUE_TREASURY, "Set Revenue treasury address");
    assertEq(smartTreasury.devTreasury(), DEV_TREASURY, "Set Dev treasury address");
    assertEq(smartTreasury.burnTreasury(), BURN_TREASURY, "Set Burn treasury address");

    vm.expectRevert(ISmartTreasury.SmartTreasury_InvalidAddress.selector);
    smartTreasury.setTreasuryAddresses(address(0), DEV_TREASURY, BURN_TREASURY);

    vm.expectRevert(ISmartTreasury.SmartTreasury_InvalidAddress.selector);
    smartTreasury.setTreasuryAddresses(REVENUE_TREASURY, address(0), BURN_TREASURY);

    vm.expectRevert(ISmartTreasury.SmartTreasury_InvalidAddress.selector);
    smartTreasury.setTreasuryAddresses(REVENUE_TREASURY, DEV_TREASURY, address(0));

    vm.stopPrank();
  }

  function testCorrectness_SetSlippageTolerances_ShouldWork() external {
    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;
    vm.prank(DEPLOYER);
    smartTreasury.setWhitelistedCallers(_callers, true);

    vm.startPrank(ALICE);
    smartTreasury.setSlippageToleranceBps(100);
    assertEq(smartTreasury.slippageToleranceBps(), 100, "Slippage tolerance");

    vm.expectRevert(ISmartTreasury.SmartTreasury_SlippageTolerance.selector);
    smartTreasury.setSlippageToleranceBps(10001);

    vm.stopPrank();
  }

  function testRevert_UnauthorizedCallerCallSetter() external {
    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;
    vm.prank(DEPLOYER);
    smartTreasury.setWhitelistedCallers(_callers, true);

    vm.startPrank(BOB);
    vm.expectRevert(ISmartTreasury.SmartTreasury_Unauthorized.selector);
    smartTreasury.setRevenueToken(address(wbnb));

    vm.expectRevert(ISmartTreasury.SmartTreasury_Unauthorized.selector);
    smartTreasury.setAllocPoints(100, 100, 100);

    vm.expectRevert(ISmartTreasury.SmartTreasury_Unauthorized.selector);
    smartTreasury.setTreasuryAddresses(REVENUE_TREASURY, DEV_TREASURY, BURN_TREASURY);

    vm.expectRevert(ISmartTreasury.SmartTreasury_Unauthorized.selector);
    smartTreasury.setSlippageToleranceBps(100);

    vm.stopPrank();
  }

  function testRevert_NonOwnerSetWhitelist_ShouldRevert() external {
    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;
    vm.expectRevert("Ownable: caller is not the owner");
    smartTreasury.setWhitelistedCallers(_callers, true);
  }
}
