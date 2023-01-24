// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, console, LYFDiamond, ILYFAdminFacet } from "./LYF_BaseTest.t.sol";

// interfaces
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";

contract LYF_Admin_SetDebtShareIdTest is LYF_BaseTest {
  function setUp() public override {
    super.setUp();
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
}
