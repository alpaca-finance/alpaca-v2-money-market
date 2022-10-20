// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20 } from "./MoneyMarket_BaseTest.t.sol";

// interfaces
import { IBorrowFacet, LibCollateraleralDoublyLinkedList } from "../../contracts/money-market/facets/BorrowFacet.sol";

contract MoneyMarket_BorrowFacetTest is MoneyMarket_BaseTest {
  uint256 subAccount0 = 0;
  MockERC20 mockToken;

  function setUp() public override {
    super.setUp();

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    mockToken.approve(moneyMarketDiamond, type(uint256).max);

    weth.approve(moneyMarketDiamond, 10 ether);
    depositFacet.deposit(address(weth), 10 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserBorrowTokenFromMM_ShouldTransferTokenToUser()
    external
  {
    uint256 _borrowAmount = 10 ether;
    uint256 _bobBalanceBefore = weth.balanceOf(BOB);
    vm.startPrank(BOB);
    borrowFacet.borrow(BOB, subAccount0, address(weth), _borrowAmount);
    vm.stopPrank();

    uint256 _bobBalanceAfter = weth.balanceOf(BOB);

    assertEq(_bobBalanceAfter - _bobBalanceBefore, _borrowAmount);
  }
}
