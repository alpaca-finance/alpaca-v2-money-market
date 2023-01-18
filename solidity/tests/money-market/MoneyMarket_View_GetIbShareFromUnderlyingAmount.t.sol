// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, console } from "./MoneyMarket_BaseTest.t.sol";

// mocks
import { MockInterestModel } from "../mocks/MockInterestModel.sol";

contract MoneyMarket_View_getIbShareFromUnderlyingAmount is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_GetIbShareFromUnderlyingAmount_ShouldReturnCorrectShareAmount() external {
    MockInterestModel _interestModel = new MockInterestModel(0.01 ether);
    adminFacet.setInterestModel(address(weth), address(_interestModel));

    vm.prank(ALICE);
    lendFacet.deposit(address(weth), 2 ether);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), 10 ether);
    borrowFacet.borrow(subAccount0, address(weth), 1 ether);
    vm.stopPrank();

    vm.warp(block.timestamp + 10 seconds);

    // 10 seconds pass with interest 0.01 per sec
    // totalToken = 2 * 0.01 * 10 = 2.1
    // 2 underlyingToken = 2*2/2.1 = 1.904761904761904761 ibToken
    assertEq(viewFacet.getIbShareFromUnderlyingAmount(address(weth), 2 ether), 1.904761904761904761 ether);
  }
}
