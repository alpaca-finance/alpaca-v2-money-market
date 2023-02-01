// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { IAdminFacet } from "../../contracts/money-market/interfaces/IAdminFacet.sol";

contract MoneyMarket_Admin_SetTreasuryTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testRevert_WhenNonAdminSetTreasury_ShouldRevert() external {
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setTreasury(address(1));
  }

  function testRevert_WhenAdminSetTreasuryWithZeroAddress_ShouldRevert() external {
    vm.expectRevert(abi.encodeWithSelector(IAdminFacet.AdminFacet_InvalidAddress.selector));
    adminFacet.setTreasury(address(0));
  }

  function testCorrectness_WhenAdminSetTreasury_ShouldWork() external {
    address _mockTreasuryAddress = address(1);
    adminFacet.setTreasury(_mockTreasuryAddress);

    // viewFacet.getl
  }
}
