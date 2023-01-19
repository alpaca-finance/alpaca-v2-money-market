// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, console, LYFDiamond, ILYFAdminFacet } from "./LYF_BaseTest.t.sol";

// interfaces
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";

import { MockAlpacaV2Oracle } from "../mocks/MockAlpacaV2Oracle.sol";
import { MockInterestModel } from "../mocks/MockInterestModel.sol";

contract LYF_AdminFacetTest is LYF_BaseTest {
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

  function testCorrectness_WhenNonAdminSetSomeLYFConfig_ShouldRevert() external {
    vm.startPrank(ALICE);

    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setOracle(address(8888));

    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setMinDebtSize(200 ether);

    vm.stopPrank();
  }

  function testRevert_WhenAdminSetDebtShareIdThatHasBeenSet_ShouldRevert() external {
    vm.expectRevert(ILYFAdminFacet.LYFAdminFacet_BadDebtShareId.selector);
    adminFacet.setDebtShareId(address(weth), address(wethUsdcLPToken), 1);
  }

  function testRevert_WhenAdminSetDebtShareIdForDifferentToken_ShouldRevert() external {
    vm.expectRevert(ILYFAdminFacet.LYFAdminFacet_BadDebtShareId.selector);
    adminFacet.setDebtShareId(address(usdc), address(8888), 1);
  }

  function testCorrectness_WhenAdminSetDebtShareIdForSameToken_ShouldWork() external {
    adminFacet.setDebtShareId(address(weth), address(8888), 1);
  }

  function testRevert_WhenAdminSetInvalidDebtShareId() external {
    vm.expectRevert(ILYFAdminFacet.LYFAdminFacet_BadDebtShareId.selector);
    adminFacet.setDebtShareId(address(usdc), address(8888), 0);
    vm.expectRevert(ILYFAdminFacet.LYFAdminFacet_BadDebtShareId.selector);
    adminFacet.setDebtShareId(address(usdc), address(8888), type(uint256).max);
  }

  function testCorrectness_WhenLYFAdminSetMaxNumOfToken_ShouldCorrect() external {
    assertEq(viewFacet.getMaxNumOfToken(), 3); // 3 is set from basetest
    adminFacet.setMaxNumOfToken(10);
    assertEq(viewFacet.getMaxNumOfToken(), 10);
  }

  function testCorrectness_WhenLYFAdminSetMinDebtSize_ShouldCorrect() external {
    assertEq(viewFacet.getMinDebtSize(), 0); // 3 is set from basetest
    adminFacet.setMinDebtSize(200 ether);
    assertEq(viewFacet.getMinDebtSize(), 200 ether);
  }

  function testCorrectness_WhenSetDebtInterestModel() external {
    adminFacet.setDebtInterestModel(1, address(new MockInterestModel(0)));
  }

  function testRevert_WhenSetDebtInterestModel() external {
    // not passed sanity check
    vm.expectRevert();
    adminFacet.setDebtInterestModel(1, address(8888));

    // setter is not owner
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setDebtInterestModel(0, address(8888));
  }
}
