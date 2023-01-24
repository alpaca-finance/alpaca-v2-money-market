// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, console, LYFDiamond, ILYFAdminFacet } from "./LYF_BaseTest.t.sol";

// interfaces
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";

contract LYF_Admin_SetMaxNumOfTokenTest is LYF_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenLYFAdminSetMaxNumOfToken_ShouldCorrect() external {
    assertEq(viewFacet.getMaxNumOfToken(), 3); // 3 is set from basetest
    adminFacet.setMaxNumOfToken(10, 10);
    assertEq(viewFacet.getMaxNumOfToken(), 10);
  }
}
