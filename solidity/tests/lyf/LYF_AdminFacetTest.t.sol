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
      reinvestThreshold: reinvestThreshold,
      rewardToken: address(cake),
      poolId: wethUsdcPoolId
    });

    adminFacet.setLPConfigs(_lpConfigs);

    LibLYF01.LPConfig memory _lpConfig = viewFacet.getLpTokenConfig(address(wethUsdcLPToken));

    assertEq(_lpConfig.poolId, _lpConfigs[0].poolId);
  }
}
