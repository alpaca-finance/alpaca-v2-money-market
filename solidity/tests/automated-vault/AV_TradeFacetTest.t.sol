// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { AV_BaseTest, console } from "./AV_BaseTest.t.sol";

import { LibAV01 } from "../../contracts/automated-vault/libraries/LibAV01.sol";

contract AV_TradeFacetTest is AV_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenDepositToken_ShouldWork() external {
    vm.prank(ALICE);
    tradeFacet.deposit(address(avShareToken), 10 ether, 10 ether);

    // leverage level is 3
    // price of weth and usdc are 1 USD
    // to calculate borrowed statble token, depositedAmount * leverageLevel - depositedAmount
    // then borrowed stable token is 10 * 3 - 10 = 20
    // to calculate borrowed asset token, depositedAmount * leverageLevel
    // then borrowed asset token is 10 * 3 = 30
    (uint256 _stableDebtValue, uint256 _assetDebtValue) = tradeFacet.getDebtValues(address(avShareToken));
    assertEq(_stableDebtValue, 20 ether);
    assertEq(_assetDebtValue, 30 ether);

    // equity change
    // before deposit
    // lpAmountPrice = 2, wethPrice = 1, usdcPrice = 1
    // lpAmount = 0, wethDebtAmount = 0, usdcDebtAmount = 0
    // equityBefore = (0 * 2) - ((0 * 1) + (0 * 1)) = 0
    // after deposit
    // lpAmount = 30, wethDebtAmount = 20, usdcDebtAmount = 30
    // equityAfter = (30 * 2) - ((20 * 1) + (30 * 1)) = 60 - 50 = 10
    // equity change = 10
    // avToken totalSupply = 0
    // given shareToMint = equityChange * totalSupply (avToken) / totalEquity
    // in this case is first mint, so shareToMint will be equityChange
    // shareToMint = 10
    assertEq(avShareToken.balanceOf(ALICE), 10 ether);

    // check liquidty in handler, 30 + 30 / 2 = 30
    assertEq(handler.totalLpBalance(), 30 ether);
  }

  function testRevert_WhenDepositTokenAndGetTonyShares_ShouldRevert() external {
    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(LibAV01.LibAV01_NoTinyShares.selector));
    tradeFacet.deposit(address(avShareToken), 0.05 ether, 0.05 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenWithdrawToken_ShouldWork() external {
    vm.startPrank(ALICE);
    tradeFacet.deposit(address(avShareToken), 1 ether, 0);
    tradeFacet.withdraw(address(avShareToken), 1 ether, 0);
    vm.stopPrank();
  }

  // TODO: test management fee to treasury
}
