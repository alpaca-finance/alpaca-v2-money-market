// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, console, ILYFAdminFacet } from "./LYF_BaseTest.t.sol";

contract LYF_Admin_SetDebtShareIdTest is LYF_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testRevert_WhenAdminSetDebtShareIdThatHasBeenSet_ShouldRevert() external {
    vm.expectRevert(ILYFAdminFacet.LYFAdminFacet_BadDebtPoolId.selector);
    adminFacet.setDebtPoolId(address(weth), address(wethUsdcLPToken), 1);
  }

  function testRevert_WhenAdminSetDebtShareIdForDifferentToken_ShouldRevert() external {
    vm.expectRevert(ILYFAdminFacet.LYFAdminFacet_BadDebtPoolId.selector);
    adminFacet.setDebtPoolId(address(usdc), address(8888), 1);
  }

  function testCorrectness_WhenAdminSetDebtShareIdForSameToken_ShouldWork() external {
    adminFacet.setDebtPoolId(address(weth), address(8888), 1);
  }

  function testRevert_WhenAdminSetInvalidDebtShareId() external {
    vm.expectRevert(ILYFAdminFacet.LYFAdminFacet_BadDebtPoolId.selector);
    adminFacet.setDebtPoolId(address(usdc), address(8888), 0);
    vm.expectRevert(ILYFAdminFacet.LYFAdminFacet_BadDebtPoolId.selector);
    adminFacet.setDebtPoolId(address(usdc), address(8888), type(uint256).max);
  }
}
