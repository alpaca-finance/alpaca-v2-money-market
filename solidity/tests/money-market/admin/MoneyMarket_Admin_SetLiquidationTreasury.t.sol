// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest } from "../MoneyMarket_BaseTest.t.sol";

// interfaces
import { IAdminFacet } from "../../../contracts/money-market/interfaces/IAdminFacet.sol";

contract MoneyMarket_Admin_SetLiquidationTreasuryTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testRevert_WhenNonAdminSetLiquidationTreasury_ShouldRevert() external {
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setLiquidationTreasury(address(1));
  }

  function testRevert_WhenAdminSetLiquidationTreasuryWithZeroAddress_ShouldRevert() external {
    vm.expectRevert(abi.encodeWithSelector(IAdminFacet.AdminFacet_InvalidAddress.selector));
    adminFacet.setLiquidationTreasury(address(0));
  }

  function testCorrectness_WhenAdminSetLiquidationTreasury_ShouldWork() external {
    address _mockTreasuryAddress = address(1);
    adminFacet.setLiquidationTreasury(_mockTreasuryAddress);

    assertEq(viewFacet.getLiquidationTreasury(), _mockTreasuryAddress);
  }
}
