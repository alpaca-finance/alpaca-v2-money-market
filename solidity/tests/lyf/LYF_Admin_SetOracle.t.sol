// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, console } from "./LYF_BaseTest.t.sol";

import { MockAlpacaV2Oracle } from "../mocks/MockAlpacaV2Oracle.sol";
import { MockInterestModel } from "../mocks/MockInterestModel.sol";

contract LYF_Admin_SetOracleTest is LYF_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenAdminSetPriceOracle_ShouldWork() external {
    address _oracleAddress = address(new MockAlpacaV2Oracle());

    adminFacet.setOracle(_oracleAddress);

    assertEq(viewFacet.getOracle(), _oracleAddress);
  }

  function testRevert_WhenAdminSetPriceOracleWithInvalidContrac() external {
    address _oracleAddress = address(8888);

    vm.expectRevert();
    adminFacet.setOracle(_oracleAddress);
  }

  function testRevert_WhenNonAdminSetOracle_ShouldRevert() external {
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setOracle(address(8888));
  }
}
