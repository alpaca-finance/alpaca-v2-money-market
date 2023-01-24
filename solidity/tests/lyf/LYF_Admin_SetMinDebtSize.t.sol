// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, console, LYFDiamond, ILYFAdminFacet } from "./LYF_BaseTest.t.sol";

// interfaces
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";

contract LYF_Admin_SetMinDebtSizeTest is LYF_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testRevert_WhenNonAdminSetMinDebtSize_ShouldRevert() external {
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setMinDebtSize(200 ether);
  }

  function testCorrectness_WhenLYFAdminSetMinDebtSize_ShouldCorrect() external {
    assertEq(viewFacet.getMinDebtSize(), 0.01 ether); // set from basetest
    adminFacet.setMinDebtSize(200 ether);
    assertEq(viewFacet.getMinDebtSize(), 200 ether);
  }
}
