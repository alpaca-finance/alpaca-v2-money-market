// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";

// interfaces
import { IDepositFacet } from "../../contracts/money-market/facets/DepositFacet.sol";

contract MoneyMarket_DepositFacetTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenUserDeposit_TokenShouldSafeTransferFromUserToMM()
    external
  {
    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, 10 ether);
    depositFacet.deposit(address(weth), 10 ether);
    vm.stopPrank();

    assertEq(weth.balanceOf(ALICE), 990 ether);
    assertEq(weth.balanceOf(moneyMarketDiamond), 10 ether);

    assertEq(ibWeth.balanceOf(ALICE), 10 ether);
  }

  function testRevert_WhenUserDepositInvalidToken_ShouldRevert() external {
    address _randomToken = address(10);
    vm.startPrank(ALICE);
    vm.expectRevert(
      abi.encodeWithSelector(
        IDepositFacet.DepositFacet_InvalidToken.selector,
        _randomToken
      )
    );
    depositFacet.deposit(_randomToken, 10 ether);
    vm.stopPrank();
  }
}
