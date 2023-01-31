// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, console, LYFDiamond, ILYFAdminFacet } from "./LYF_BaseTest.t.sol";

// interfaces
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";

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

    LibLYF01.LPConfig memory _lpConfig = viewFacet.getLpTokenConfig(address(wethUsdcLPToken));

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
      reinvestTreasuryBountyBps: uint16(LibLYF01.MAX_BPS) + 1
    });
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
      reinvestTreasuryBountyBps: uint16(LibLYF01.MAX_BPS) + 1
    });
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setLPConfigs(_lpConfigs);
  }
}
