// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, console, LYFDiamond } from "./LYF_BaseTest.t.sol";

// interfaces
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";

contract LYF_AdminFacetTest is LYF_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenAdminSetPriceOracle_ShouldWork() external {
    address _oracleAddress = address(20000);

    adminFacet.setOracle(_oracleAddress);

    assertEq(adminFacet.oracle(), _oracleAddress);
  }
}
