// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { LYF_BaseTest, console, ILYFAdminFacet } from "./LYF_BaseTest.t.sol";

// lib
import { LibLYFConstant } from "../../contracts/lyf/libraries/LibLYFConstant.sol";

contract LYF_Admin_SetTokenConfigsTest is LYF_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_SetTokenConfigs_ShouldWork() external {
    ILYFAdminFacet.TokenConfigInput[] memory _inputs = new ILYFAdminFacet.TokenConfigInput[](1);
    _inputs[0] = ILYFAdminFacet.TokenConfigInput({
      token: address(weth),
      tier: LibLYFConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxCollateral: 100 ether
    });
    adminFacet.setTokenConfigs(_inputs);
  }

  function testRevert_SetTokenConfigsWithInvalidaArgs() external {
    ILYFAdminFacet.TokenConfigInput[] memory _inputs = new ILYFAdminFacet.TokenConfigInput[](1);

    // invalid collatFactor
    _inputs[0] = ILYFAdminFacet.TokenConfigInput({
      token: address(weth),
      tier: LibLYFConstant.AssetTier.COLLATERAL,
      collateralFactor: uint16(LibLYFConstant.MAX_BPS) + 1,
      borrowingFactor: 9000,
      maxCollateral: 100 ether
    });
    vm.expectRevert(ILYFAdminFacet.LYFAdminFacet_InvalidArguments.selector);
    adminFacet.setTokenConfigs(_inputs);

    // invalid borrowingFactor (exceed max bps)
    _inputs[0].collateralFactor = 9000;
    _inputs[0].borrowingFactor = uint16(LibLYFConstant.MAX_BPS) + 1;
    vm.expectRevert(ILYFAdminFacet.LYFAdminFacet_InvalidArguments.selector);
    adminFacet.setTokenConfigs(_inputs);

    // invalid borrowingFactor (equal zero)
    _inputs[0].borrowingFactor = 0;
    vm.expectRevert(ILYFAdminFacet.LYFAdminFacet_InvalidArguments.selector);
    adminFacet.setTokenConfigs(_inputs);

    // invalid maxCollat
    _inputs[0].borrowingFactor = 9000;
    _inputs[0].maxCollateral = 1e40 + 1;
    vm.expectRevert(ILYFAdminFacet.LYFAdminFacet_InvalidArguments.selector);
    adminFacet.setTokenConfigs(_inputs);
  }

  function testRevert_WhenNonAdminSetTokenConfigs() external {
    ILYFAdminFacet.TokenConfigInput[] memory _inputs = new ILYFAdminFacet.TokenConfigInput[](1);
    _inputs[0] = ILYFAdminFacet.TokenConfigInput({
      token: address(weth),
      tier: LibLYFConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxCollateral: 100 ether
    });
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setTokenConfigs(_inputs);
  }
}
