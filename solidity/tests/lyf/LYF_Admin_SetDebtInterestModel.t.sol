// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, console, ILYFAdminFacet } from "./LYF_BaseTest.t.sol";

// interfaces
import { MockInterestModel } from "../mocks/MockInterestModel.sol";

contract LYF_Admin_SetDebtInterestModelTest is LYF_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenSetDebtInterestModel() external {
    adminFacet.setDebtPoolInterestModel(1, address(new MockInterestModel(0)));
  }

  function testRevert_WhenSetDebtInterestModel() external {
    // not passed sanity check
    vm.expectRevert();
    adminFacet.setDebtPoolInterestModel(1, address(8888));

    // setter is not owner
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setDebtPoolInterestModel(0, address(8888));
  }
}
