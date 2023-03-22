// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { LYF_BaseTest, console, ILYFAdminFacet } from "./LYF_BaseTest.t.sol";

// lib
import { LibLYFConstant } from "../../contracts/lyf/libraries/LibLYFConstant.sol";

contract LYF_Admin_SetLpConfigsTest is LYF_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_SetLPConfigs_ShouldWork() external {
    address[] memory _reinvestPath = new address[](2);
    _reinvestPath[0] = address(cake);
    _reinvestPath[1] = address(usdc);

    ILYFAdminFacet.LPConfigInput[] memory _lpConfigs = new ILYFAdminFacet.LPConfigInput[](1);
    _lpConfigs[0] = ILYFAdminFacet.LPConfigInput({
      lpToken: address(wethUsdcLPToken),
      strategy: address(addStrat),
      masterChef: address(masterChef),
      router: address(mockRouter),
      reinvestPath: _reinvestPath,
      rewardToken: address(cake),
      poolId: wethUsdcPoolId,
      maxLpAmount: 1_000 ether,
      reinvestThreshold: reinvestThreshold,
      reinvestTreasuryBountyBps: 1500
    });

    adminFacet.setLPConfigs(_lpConfigs);

    LibLYFConstant.LPConfig memory _lpConfig = viewFacet.getLpTokenConfig(address(wethUsdcLPToken));

    assertEq(_lpConfig.poolId, _lpConfigs[0].poolId);
  }

  function testRevert_SetLPConfigsWithInvalidArgs() external {
    address[] memory _reinvestPath = new address[](2);
    _reinvestPath[0] = address(cake);
    _reinvestPath[1] = address(usdc);

    // invalid reinvestTreasuryBountyBps
    ILYFAdminFacet.LPConfigInput[] memory _lpConfigs = new ILYFAdminFacet.LPConfigInput[](1);
    _lpConfigs[0] = ILYFAdminFacet.LPConfigInput({
      lpToken: address(wethUsdcLPToken),
      strategy: address(addStrat),
      masterChef: address(masterChef),
      router: address(mockRouter),
      reinvestPath: _reinvestPath,
      rewardToken: address(cake),
      poolId: wethUsdcPoolId,
      maxLpAmount: 1_000 ether,
      reinvestThreshold: reinvestThreshold,
      reinvestTreasuryBountyBps: uint16(LibLYFConstant.MAX_BPS) + 1
    });
    vm.expectRevert(ILYFAdminFacet.LYFAdminFacet_InvalidArguments.selector);
    adminFacet.setLPConfigs(_lpConfigs);

    // reinvestPath[0] != rewardToken
    _lpConfigs[0].reinvestTreasuryBountyBps = 100;
    _reinvestPath[0] = address(weth);
    vm.expectRevert(ILYFAdminFacet.LYFAdminFacet_InvalidArguments.selector);
    adminFacet.setLPConfigs(_lpConfigs);
  }

  function testRevert_WhenNonAdminSetLPConfigs() external {
    address[] memory _reinvestPath = new address[](2);
    _reinvestPath[0] = address(cake);
    _reinvestPath[1] = address(usdc);

    ILYFAdminFacet.LPConfigInput[] memory _lpConfigs = new ILYFAdminFacet.LPConfigInput[](1);
    _lpConfigs[0] = ILYFAdminFacet.LPConfigInput({
      lpToken: address(wethUsdcLPToken),
      strategy: address(addStrat),
      masterChef: address(masterChef),
      router: address(mockRouter),
      reinvestPath: _reinvestPath,
      rewardToken: address(cake),
      poolId: wethUsdcPoolId,
      maxLpAmount: 1_000 ether,
      reinvestThreshold: reinvestThreshold,
      reinvestTreasuryBountyBps: uint16(LibLYFConstant.MAX_BPS) + 1
    });
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setLPConfigs(_lpConfigs);
  }
}
