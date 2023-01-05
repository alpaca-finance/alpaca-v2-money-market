// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { AV_BaseTest, console } from "./AV_BaseTest.t.sol";

import { IAVTradeFacet } from "../../contracts/automated-vault/interfaces/IAVTradeFacet.sol";

import { LibAV01 } from "../../contracts/automated-vault/libraries/LibAV01.sol";

contract AV_Trade_WithdrawalTest is AV_BaseTest {
  function setUp() public override {
    super.setUp();
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

  function testRevert_WhenWithdrawAndGetTokenLessThanExpectation_ShouldRevert() external {
    vm.startPrank(ALICE);
    tradeFacet.deposit(address(avShareToken), 10 ether, 10 ether);

    mockRouter.setRemoveLiquidityAmountsOut(1 ether, 7.5 ether);

    vm.expectRevert(abi.encodeWithSelector(IAVTradeFacet.AVTradeFacet_WithdrawalAmountTooLow.selector));
    tradeFacet.withdraw(address(avShareToken), 5 ether, 5 ether);

    vm.stopPrank();
  }

  function testRevert_WhenWithdrawAndReturnedLessThanExpectation_ShouldRevert() external {
    vm.startPrank(ALICE);
    tradeFacet.deposit(address(avShareToken), 10 ether, 10 ether);

    vm.expectRevert(abi.encodeWithSelector(IAVTradeFacet.AVTradeFacet_TooLittleReceived.selector));
    tradeFacet.withdraw(address(avShareToken), 5 ether, type(uint256).max);

    vm.stopPrank();
  }
}
