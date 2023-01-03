// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { IAdminFacet } from "../../contracts/money-market/interfaces/IAdminFacet.sol";

contract MoneyMarket_Admin_SetMinUsedBorrowingPowerTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenAdminSetMinUsedBorrowingPower_ShouldWork() external {
    // 0.1 set by mm base test
    assertEq(viewFacet.getMinUsedBorrowingPower(), 0.1 ether);

    adminFacet.setMinUsedBorrowingPower(1 ether);

    assertEq(viewFacet.getMinUsedBorrowingPower(), 1 ether);
  }

  function testRevert_WhenNonAdminSetMinUsedBorrowingPower() external {
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setMinUsedBorrowingPower(1 ether);
  }
}
