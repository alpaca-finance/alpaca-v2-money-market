// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { AV_BaseTest, console } from "./AV_BaseTest.t.sol";

import { LibAV01 } from "../../contracts/automated-vault/libraries/LibAV01.sol";
import { IAVTradeFacet } from "../../contracts/automated-vault/interfaces/IAVTradeFacet.sol";

/** 
  Test cases
  deposit passed case - testCorrectness_WhenDepositToken_ShouldWork
  deposit revert case: tiny amount - testRevert_WhenDepositTokenAndGetTinyShares_ShouldRevert
  withdraw passed case: testCorrectness_WhenWithdrawToken_ShouldWork
  withdraw revert case: too much returned amount - testRevert_WhenWithdrawAndReturnedLessThanExpectation_ShouldRevert
  withdraw revert case: get too low amount after remove liquidity - testRevert_WhenWithdrawAndGetTokenLessThanExpectation_ShouldRevert
  management fee passed case: get pending correctly - testCorrectness_GetPendingManagementFee
  management fee passed case: fee is corrected when withdraw - testCorrectness_WhenDepositAndWithdraw_ShouldMintPendingManagementFeeToTreasury
**/
contract AV_TradeFacetTest is AV_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenDepositToken_ShouldWork() external {
    uint256 aliceUsdcBefore = usdc.balanceOf(ALICE);
    vm.prank(ALICE);
    tradeFacet.deposit(address(avShareToken), 10 ether, 10 ether);

    // should get funds from user correctly
    assertEq(aliceUsdcBefore - usdc.balanceOf(ALICE), 10 ether);

    // leverage level is 3
    // price of weth and usdc are 1 USD
    // to calculate borrowed statble token, depositedAmount * leverageLevel - depositedAmount
    // target value = 10 * 3 = 30, then each side has borrowed value 30 / 2 = 15
    // then borrowed stable token is 15 - 10 = 5
    // to calculate borrowed asset token, depositedAmount * leverageLevel
    // then borrowed asset token is 15
    (uint256 _stableDebtValue, uint256 _assetDebtValue) = tradeFacet.getDebtValues(address(avShareToken));
    assertEq(_stableDebtValue, 5 ether);
    assertEq(_assetDebtValue, 15 ether);

    // equity change
    // before deposit
    // lpAmountPrice = 2, wethPrice = 1, usdcPrice = 1
    // lpAmount = 0, wethDebtAmount = 0, usdcDebtAmount = 0
    // equityBefore = (0 * 2) - ((0 * 1) + (0 * 1)) = 0
    // after deposit
    // lpAmount = 15, wethDebtAmount = 5, usdcDebtAmount = 15
    // equityAfter = (15 * 2) - ((5 * 1) + (15 * 1)) = 30 - 20 = 10
    // equity change = 10
    // avToken totalSupply = 0
    // given shareToMint = equityChange * totalSupply (avToken) / totalEquity
    // in this case is first mint, so shareToMint will be equityChange
    // shareToMint = 10
    assertEq(avShareToken.balanceOf(ALICE), 10 ether);

    // note: for mock router compose LP
    // check liquidty in handler, 15 + 15 / 2 = 15
    assertEq(handler.totalLpBalance(), 15 ether);
  }

  function testRevert_WhenDepositTokenAndGetTinyShares_ShouldRevert() external {
    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(LibAV01.LibAV01_NoTinyShares.selector));
    tradeFacet.deposit(address(avShareToken), 0.05 ether, 0.05 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenWithdrawToken_ShouldWork() external {
    vm.prank(ALICE);
    tradeFacet.deposit(address(avShareToken), 10 ether, 10 ether);

    (uint256 _stableDebtValueBefore, uint256 _assetDebtValueBefore) = tradeFacet.getDebtValues(address(avShareToken));

    // after deposit, ref: from test testCorrectness_WhenDepositToken_ShouldWork
    // lpAmountPrice = 2, wethPrice = 1, usdcPrice = 1
    // lpAmount = 15, wethDebtAmount = 5, usdcDebtAmount = 15
    // equity = (15 * 2) - ((5 * 1) + (15 * 1)) = 30 - (5 + 15) = 10
    // then equity ratio = equity / total lp value = 10 / (15 * 2) = 0.333333333333333333
    // share to withdraw = 5, then shareValueToRemove = 5 * 10 (equity) / 10 (totalSupply) = 5 USD
    // then lpValueToRemove = shareToken / equity ratio = 5 / 0.333333333333333333 = 15.000000000000000015
    // then lpToRemove = 15.000000000000000015 / 2 (lpTokenPrice) = 7.500000000000000007
    // buffer for 5% 7.500000000000000007 * 9995 / 10000 = 7.496250000000000006

    // mock router to return both tokens as 7.5 ether
    mockRouter.setRemoveLiquidityAmountsOut(7.5 ether, 7.5 ether);

    // after withdraw
    // equity should change a bit
    // before withdraw equity is 10 USD
    // after withdraw equity should be lpTotalBalance after remove = 15 - 7.500000000000000007 = 7.499999999999999993 USD
    // share to withdraw = 5, shareToken price = 1 ether, then shareValueToRemove = 5 USD
    // then user should receive stable token back about 5 / 1 (tokenPrice) = 5 TOKEN
    // note: ref amount from setRemoveLiquidityAmountsOut
    // repay debt amount (token1): 7.5, but return to user 5 TOKEN, then repay debt amount = 2.5
    // repay debt amount (token0): 7.5
    uint256 aliceUsdcBefore = usdc.balanceOf(ALICE);
    vm.prank(ALICE);
    tradeFacet.withdraw(address(avShareToken), 5 ether, 5 ether);

    assertEq(avShareToken.balanceOf(ALICE), 5 ether);
    // alice should get correct token return amount
    assertEq(usdc.balanceOf(ALICE) - aliceUsdcBefore, 5 ether);

    // should repay correctly
    (uint256 _stableDebtValueAfter, uint256 _assetDebtValueAfter) = tradeFacet.getDebtValues(address(avShareToken));
    assertEq(_stableDebtValueBefore - _stableDebtValueAfter, 2.5 ether);
    assertEq(_assetDebtValueBefore - _assetDebtValueAfter, 7.5 ether);

    // 15 - 7.496250000000000006 = 7.503749999999999994
    assertEq(handler.totalLpBalance(), 7.503749999999999994 ether);
  }

  function testRevert_WhenWithdrawAndReturnedLessThanExpectation_ShouldRevert() external {
    vm.startPrank(ALICE);
    tradeFacet.deposit(address(avShareToken), 10 ether, 10 ether);

    vm.expectRevert(abi.encodeWithSelector(IAVTradeFacet.AVTradeFacet_TooLittleReceived.selector));
    tradeFacet.withdraw(address(avShareToken), 5 ether, type(uint256).max);

    vm.stopPrank();
  }

  function testRevert_WhenWithdrawAndGetTokenLessThanExpectation_ShouldRevert() external {
    vm.startPrank(ALICE);
    tradeFacet.deposit(address(avShareToken), 10 ether, 10 ether);

    mockRouter.setRemoveLiquidityAmountsOut(1 ether, 7.5 ether);

    vm.expectRevert(abi.encodeWithSelector(IAVTradeFacet.AVTradeFacet_InsufficientAmount.selector));
    tradeFacet.withdraw(address(avShareToken), 5 ether, 5 ether);

    vm.stopPrank();
  }

  // managment fee tests
  function testCorrectness_GetPendingManagementFee() external {
    // managementFeePerSec = 1, set in AV_BaseTest

    // block.timestamp = 1
    assertEq(tradeFacet.pendingManagementFee(address(avShareToken)), 0); // totalSupply(avShareToken) = 0

    vm.prank(avDiamond);
    avShareToken.mint(address(this), 1 ether);
    assertEq(tradeFacet.pendingManagementFee(address(avShareToken)), 1);

    // block.timestamp = 2
    vm.warp(2);
    assertEq(tradeFacet.pendingManagementFee(address(avShareToken)), 2);
  }

  function testCorrectness_WhenDepositAndWithdraw_ShouldMintPendingManagementFeeToTreasury() external {
    assertEq(tradeFacet.pendingManagementFee(address(avShareToken)), 0);

    vm.prank(ALICE);
    tradeFacet.deposit(address(avShareToken), 5 ether, 5 ether);

    assertEq(tradeFacet.pendingManagementFee(address(avShareToken)), 0); // fee was collected during deposit, so no more pending fee in the same block
    assertEq(avShareToken.balanceOf(treasury), 0);

    vm.warp(2);
    vm.prank(ALICE);
    tradeFacet.deposit(address(avShareToken), 5 ether, 5 ether); // fee should distribute if deposit again

    assertEq(tradeFacet.pendingManagementFee(address(avShareToken)), 0);
    assertEq(avShareToken.balanceOf(treasury), 5);

    vm.warp(3);
    assertEq(tradeFacet.pendingManagementFee(address(avShareToken)), 10);

    mockRouter.setRemoveLiquidityAmountsOut(7.5 ether, 7.5 ether);

    vm.prank(ALICE);
    tradeFacet.withdraw(address(avShareToken), 5 ether, 0);

    assertEq(tradeFacet.pendingManagementFee(address(avShareToken)), 0);
    assertEq(avShareToken.balanceOf(treasury), 15);
  }
}
