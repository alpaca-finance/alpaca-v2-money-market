// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { LYF_BaseTest, console, ILYFAdminFacet } from "./LYF_BaseTest.t.sol";

contract LYF_Admin_SetMaxNumOfTokenTest is LYF_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenLYFAdminSetMaxNumOfToken_ShouldCorrect() external {
    (uint8 _maxNumOfCollat, uint8 _maxNumOfDebt) = viewFacet.getMaxNumOfToken();
    assertEq(_maxNumOfCollat, 3); // 3 is set from basetest
    assertEq(_maxNumOfDebt, 3); // 3 is set from basetest
    adminFacet.setMaxNumOfToken(10, 10);
    (_maxNumOfCollat, _maxNumOfDebt) = viewFacet.getMaxNumOfToken();
    assertEq(_maxNumOfCollat, 10);
    assertEq(_maxNumOfDebt, 10);
  }
}
