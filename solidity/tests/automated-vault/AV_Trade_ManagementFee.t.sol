// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { AV_BaseTest, console } from "./AV_BaseTest.t.sol";

import { LibAV01 } from "../../contracts/automated-vault/libraries/LibAV01.sol";

contract AV_Trade_ManagementFeeTest is AV_BaseTest {
  function setUp() public override {
    super.setUp();

    adminFacet.setManagementFeePerSec(address(vaultToken), 1);
  }

  function testCorrectness_GetPendingManagementFee() external {
    // managementFeePerSec = 1, set in AV_BaseTest

    // block.timestamp = 1
    assertEq(viewFacet.getPendingManagementFee(address(vaultToken)), 0); // totalSupply(vaultToken) = 0

    vm.prank(ALICE);
    tradeFacet.deposit(address(vaultToken), 1 ether, 1 ether);
    assertEq(viewFacet.getPendingManagementFee(address(vaultToken)), 0);

    // time pass = 2 seconds
    vm.warp(block.timestamp + 2);
    assertEq(viewFacet.getPendingManagementFee(address(vaultToken)), 2);
  }

  function testCorrectness_WhenDepositAndWithdraw_ShouldMintPendingManagementFeeToTreasury() external {
    assertEq(viewFacet.getPendingManagementFee(address(vaultToken)), 0);

    vm.prank(ALICE);
    tradeFacet.deposit(address(vaultToken), 1 ether, 1 ether);

    assertEq(viewFacet.getPendingManagementFee(address(vaultToken)), 0); // fee was collected during deposit, so no more pending fee in the same block
    assertEq(vaultToken.balanceOf(treasury), 0);

    vm.warp(block.timestamp + 2);
    assertEq(viewFacet.getPendingManagementFee(address(vaultToken)), 2);

    mockRouter.setRemoveLiquidityAmountsOut(1 ether, 1 ether);
    vm.prank(ALICE);
    tradeFacet.withdraw(address(vaultToken), 1 ether, 0, 0);

    assertEq(viewFacet.getPendingManagementFee(address(vaultToken)), 0);
    assertEq(vaultToken.balanceOf(treasury), 2);
  }
}
