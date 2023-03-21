// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { LYF_BaseTest, console, ILYFAdminFacet } from "./LYF_BaseTest.t.sol";

contract LYF_Admin_SetRewardConversionConfig is LYF_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_SetRewardConversionConfigs_ShouldWork() external {
    address _rewardToken = address(cake);
    address[] memory _path = new address[](2);
    _path[0] = _rewardToken;
    _path[1] = address(usdc);

    ILYFAdminFacet.SetRewardConversionConfigInput[]
      memory _inputs = new ILYFAdminFacet.SetRewardConversionConfigInput[](1);
    _inputs[0] = ILYFAdminFacet.SetRewardConversionConfigInput({
      rewardToken: _rewardToken,
      router: address(mockRouter),
      path: _path
    });

    adminFacet.setRewardConversionConfigs(_inputs);
  }

  function testRevert_SetRewardConversionConfigsWithInvalidArgs() external {
    // path[0] != rewardToken
    address _rewardToken = address(cake);
    address[] memory _path = new address[](2);
    _path[0] = address(weth);
    _path[1] = address(usdc);

    ILYFAdminFacet.SetRewardConversionConfigInput[]
      memory _inputs = new ILYFAdminFacet.SetRewardConversionConfigInput[](1);
    _inputs[0] = ILYFAdminFacet.SetRewardConversionConfigInput({
      rewardToken: _rewardToken,
      router: address(mockRouter),
      path: _path
    });

    vm.expectRevert(ILYFAdminFacet.LYFAdminFacet_InvalidArguments.selector);
    adminFacet.setRewardConversionConfigs(_inputs);
  }

  function testRevert_WhenNonAdminSetRewardConversionConfigs() external {
    address _rewardToken = address(cake);
    address[] memory _path = new address[](2);
    _path[0] = _rewardToken;
    _path[1] = address(usdc);

    ILYFAdminFacet.SetRewardConversionConfigInput[]
      memory _inputs = new ILYFAdminFacet.SetRewardConversionConfigInput[](1);
    _inputs[0] = ILYFAdminFacet.SetRewardConversionConfigInput({
      rewardToken: _rewardToken,
      router: address(mockRouter),
      path: _path
    });

    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setRewardConversionConfigs(_inputs);
  }
}
