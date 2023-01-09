// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, console, LYFDiamond, ILYFAdminFacet } from "./LYF_BaseTest.t.sol";

// interfaces
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";

contract LYF_AdminFacetTest is LYF_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenAdminSetPriceOracle_ShouldWork() external {
    address _oracleAddress = address(20000);

    adminFacet.setOracle(_oracleAddress);

    assertEq(viewFacet.getOracle(), _oracleAddress);
  }

  function testCorrectness_WhenNonAdminSetSomeLYFConfig_ShouldRevert() external {
    vm.startPrank(ALICE);

    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setOracle(address(20000));

    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setMinDebtSize(200 ether);

    vm.stopPrank();
  }

  function testRevert_WhenAdminSetSebtShareIdThatHasBeenSet_ShouldRevert() external {
    vm.expectRevert(ILYFAdminFacet.LYFAdminFacet_BadDebtShareId.selector);
    adminFacet.setDebtShareId(address(weth), address(wethUsdcLPToken), 1);
  }

  function testRevert_WhenAdminSetSebtShareIdForDifferentToken_ShouldRevert() external {
    vm.expectRevert(ILYFAdminFacet.LYFAdminFacet_BadDebtShareId.selector);
    adminFacet.setDebtShareId(address(usdc), address(8888), 1);
  }

  function testCorrectness_WhenAdminSetSebtShareIdForSameToken_ShouldWork() external {
    adminFacet.setDebtShareId(address(weth), address(8888), 1);
  }

  function testCorrectness_WhenLYFAdminSetMinDebtSize_ShouldCorrect() external {
    assertEq(viewFacet.getMaxNumOfToken(), 3); // 3 is set from basetest
    adminFacet.setMaxNumOfToken(10);
    assertEq(viewFacet.getMaxNumOfToken(), 10);
  }

  function testCorrectness_WhenLYFAdminSetMaxNumOfToken_ShouldCorrect() external {
    assertEq(viewFacet.getMinDebtSize(), 0); // 3 is set from basetest
    adminFacet.setMinDebtSize(200 ether);
    assertEq(viewFacet.getMinDebtSize(), 200 ether);
  }
}
