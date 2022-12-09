// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { AV_BaseTest } from "./AV_BaseTest.t.sol";

contract AV_AdminFacetTest is AV_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenAVAdminSetId_ShouldCorrect() external {
    adminFacet.setId(1);

    assertEq(adminFacet.getId(), 1);
  }
}
