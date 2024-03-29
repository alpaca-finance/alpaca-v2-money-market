// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest } from "../MoneyMarket_BaseTest.t.sol";

// interfaces
import { IAdminFacet } from "../../../contracts/money-market/interfaces/IAdminFacet.sol";

contract MoneyMarket_Admin_TopUpTokenReserveTest is MoneyMarket_BaseTest {
  event LogTopUpTokenReserve(address indexed token, uint256 amount);

  function setUp() public override {
    super.setUp();

    weth.mint(address(this), 100 ether);
    weth.approve(moneyMarketDiamond, type(uint256).max);
  }

  function testCorrectness_WhenAdminTopUpTokenReserve_ReservesShouldIncrease() external {
    address _token = address(weth);
    uint256 _amount = 1 ether;

    uint256 _wethBalanceBefore = weth.balanceOf(address(this));

    assertEq(viewFacet.getTotalToken(_token), 0);
    assertEq(_wethBalanceBefore, 100 ether);

    vm.expectEmit(true, false, false, false, moneyMarketDiamond);
    emit LogTopUpTokenReserve(_token, _amount);
    adminFacet.topUpTokenReserve(_token, _amount);

    assertEq(viewFacet.getTotalToken(_token), _amount);
    assertEq(_wethBalanceBefore - weth.balanceOf(address(this)), _amount);
  }

  function testRevert_WhenTopUpTokenReserveWithInvalidToken() external {
    address _invalidToken = address(1234);
    vm.expectRevert(abi.encodeWithSelector(IAdminFacet.AdminFacet_InvalidToken.selector, _invalidToken));
    adminFacet.topUpTokenReserve(_invalidToken, 1 ether);
  }

  function testRevert_WhenNonAdminTopUpTokenReserve() external {
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.topUpTokenReserve(address(weth), 1 ether);
  }
}
