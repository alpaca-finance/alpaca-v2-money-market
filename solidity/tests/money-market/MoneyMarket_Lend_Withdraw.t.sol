// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { ILendFacet } from "../../contracts/money-market/facets/LendFacet.sol";
import { IERC20 } from "../../contracts/money-market/interfaces/IERC20.sol";

contract MoneyMarket_Lend_Withdraw_Test is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenUserWithdraw_ibTokenShouldBurnedAndTransferTokenToUser() external {
    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, 10 ether);
    lendFacet.deposit(address(weth), 10 ether);
    vm.stopPrank();

    assertEq(weth.balanceOf(ALICE), 990 ether);
    assertEq(weth.balanceOf(moneyMarketDiamond), 10 ether);
    assertEq(ibWeth.balanceOf(ALICE), 10 ether);

    vm.startPrank(ALICE);
    ibWeth.approve(moneyMarketDiamond, 10 ether);
    lendFacet.withdraw(address(ibWeth), 10 ether);
    vm.stopPrank();

    assertEq(ibWeth.totalSupply(), 0);
    assertEq(ibWeth.balanceOf(ALICE), 0);
    assertEq(weth.balanceOf(ALICE), 1000 ether);
  }

  function testRevert_WhenUserWithdrawInvalidibToken_ShouldRevert() external {
    address _randomToken = address(10);
    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(LibMoneyMarket01.LibMoneyMarket01_InvalidToken.selector, _randomToken));
    lendFacet.withdraw(_randomToken, 10 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenMultipleUserWithdraw_ShareShouldBurnedAndTransferTokenBackCorrectly() external {
    uint256 _depositAmount1 = 10 ether;
    uint256 _depositAmount2 = 20 ether;
    uint256 _expectedTotalShare = 0;

    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, _depositAmount1);
    lendFacet.deposit(address(weth), _depositAmount1);
    vm.stopPrank();

    // first depositor mintShare = depositAmount = 10
    _expectedTotalShare += _depositAmount1;
    assertEq(ibWeth.balanceOf(ALICE), _depositAmount1);

    vm.startPrank(BOB);
    weth.approve(moneyMarketDiamond, _depositAmount2);
    lendFacet.deposit(address(weth), _depositAmount2);
    vm.stopPrank();

    // mintShare = 20 * 10 / 10 = 20
    uint256 _expectedBoBShare = 20 ether;
    _expectedTotalShare += _expectedBoBShare;
    assertEq(ibWeth.balanceOf(BOB), 20 ether);
    assertEq(ibWeth.totalSupply(), _expectedTotalShare);

    // alice withdraw share
    vm.startPrank(ALICE);
    _expectedTotalShare -= 10 ether;
    ibWeth.approve(moneyMarketDiamond, 10 ether);
    lendFacet.withdraw(address(ibWeth), 10 ether);
    vm.stopPrank();

    assertEq(weth.balanceOf(ALICE), 1000 ether);
    assertEq(ibWeth.balanceOf(ALICE), 0);
    assertEq(ibWeth.totalSupply(), _expectedTotalShare);

    // bob withdraw share
    vm.startPrank(BOB);
    _expectedTotalShare -= 20 ether;
    ibWeth.approve(moneyMarketDiamond, 20 ether);
    lendFacet.withdraw(address(ibWeth), 20 ether);
    vm.stopPrank();

    assertEq(weth.balanceOf(BOB), 1000 ether);
    assertEq(ibWeth.balanceOf(BOB), 0);
    assertEq(ibWeth.totalSupply(), _expectedTotalShare);
  }

  function testRevert_WhenUserWithdrawAndLeftWithTinyShares_ShouldRevert() external {
    vm.startPrank(ALICE);
    lendFacet.deposit(address(weth), 1 ether);
    vm.expectRevert(abi.encodeWithSelector(LibMoneyMarket01.LibMoneyMarket01_NoTinyShares.selector));
    lendFacet.withdraw(address(ibWeth), 0.5 ether);
  }

  function testCorrectness_WhenUserWithdrawETH_ShareShouldBurnedAndTransferTokenBackCorrectly() external {
    // deposit first
    vm.prank(ALICE);
    lendFacet.depositETH{ value: 10 ether }();

    assertEq(nativeToken.balanceOf(ALICE), 0 ether);
    assertEq(ALICE.balance, 990 ether);
    assertEq(nativeToken.balanceOf(moneyMarketDiamond), 10 ether);

    assertEq(ibWNative.balanceOf(ALICE), 10 ether);

    // then withdraw 5
    vm.prank(ALICE);
    lendFacet.withdrawETH(address(ibWNative), 5 ether);

    assertEq(nativeToken.balanceOf(ALICE), 0 ether);
    assertEq(ALICE.balance, 995 ether);
    assertEq(nativeToken.balanceOf(moneyMarketDiamond), 5 ether);

    assertEq(ibWNative.balanceOf(ALICE), 5 ether);
  }
}
