// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest } from "../MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { IAdminFacet } from "../../../contracts/money-market/interfaces/IAdminFacet.sol";

contract MoneyMarket_Admin_SetMinDebtSizeTest is MoneyMarket_BaseTest {
  event LogSetMinDebtSize(uint256 _newValue);

  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenAdminSetMinDebtSize_ShouldWork() external {
    // 0.1 set by mm base test
    assertEq(viewFacet.getMinDebtSize(), 0.1 ether);

    vm.expectEmit(false, false, false, false, moneyMarketDiamond);
    emit LogSetMinDebtSize(1 ether);
    adminFacet.setMinDebtSize(1 ether);

    assertEq(viewFacet.getMinDebtSize(), 1 ether);
  }

  function testRevert_WhenNonAdminSetMinDebtSize() external {
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setMinDebtSize(1 ether);
  }
}
