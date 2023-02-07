// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest } from "./LYF_BaseTest.t.sol";

// ---- Interfaces ---- //
import { ILYFAdminFacet } from "../../contracts/lyf/interfaces/ILYFAdminFacet.sol";

contract LYF_Admin_TopUpTokenReservesTest is LYF_BaseTest {
  event LogTopUpTokenReserve(address indexed token, uint256 amount);

  function setUp() public override {
    super.setUp();

    weth.mint(address(this), 100 ether);
    weth.approve(lyfDiamond, type(uint256).max);
  }

  function testCorrectness_WhenAdminTopUpTokenReserve_ReservesShouldIncrease() external {
    address _token = address(weth);
    uint256 _amount = 1 ether;

    uint256 _adminBalanceBefore = weth.balanceOf(address(this));
    uint256 _lyfBalanceBefore = weth.balanceOf(lyfDiamond);
    uint256 _outstandingBefore = viewFacet.getOutstandingBalanceOf(_token);

    assertEq(_lyfBalanceBefore, _outstandingBefore);
    assertEq(viewFacet.getOutstandingBalanceOf(_token), 0);

    vm.expectEmit(true, false, false, true, lyfDiamond);
    emit LogTopUpTokenReserve(_token, _amount);
    adminFacet.topUpTokenReserve(_token, _amount);

    uint256 _adminBalanceAfter = weth.balanceOf(address(this));
    uint256 _lyfBalanceAfter = weth.balanceOf(lyfDiamond);
    uint256 _outstandingAfter = viewFacet.getOutstandingBalanceOf(_token);

    assertEq(_lyfBalanceAfter - _lyfBalanceBefore, _amount);
    assertEq(_outstandingAfter - _outstandingBefore, _amount);
    assertEq(_adminBalanceBefore - _adminBalanceAfter, _amount);
  }

  function testRevert_WhenNonAdminTopUpTokenReserve() external {
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.topUpTokenReserve(address(weth), 1 ether);
  }
}
