// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest } from "./LYF_BaseTest.t.sol";

// ---- Interfaces ---- //
import { ILYFAdminFacet } from "../../contracts/lyf/interfaces/ILYFAdminFacet.sol";

contract LYF_Admin_TopUpTokenReserves is LYF_BaseTest {
  event LogTopUpTokenReserve(address indexed token, uint256 amount);

  function setUp() public override {
    super.setUp();

    weth.mint(address(this), 100 ether);
    weth.approve(lyfDiamond, type(uint256).max);
  }

  function testCorrectness_WhenAdminTopUpTokenReserve_ReservesShouldIncrease() external {
    address _token = address(weth);
    uint256 _amount = 1 ether;

    assertEq(viewFacet.getReserveOf(_token), 0);
    assertEq(weth.balanceOf(address(this)), 100 ether);

    vm.expectEmit(true, false, false, true, lyfDiamond);
    emit LogTopUpTokenReserve(_token, _amount);
    adminFacet.topUpTokenReserve(_token, _amount);

    assertEq(viewFacet.getReserveOf(_token), _amount);
    assertEq(weth.balanceOf(address(this)), 100 ether - _amount);
  }

  function testRevert_WhenNonAdminTopUpTokenReserve() external {
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.topUpTokenReserve(address(weth), 1 ether);
  }
}
