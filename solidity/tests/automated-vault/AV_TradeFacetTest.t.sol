// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { AV_BaseTest, console } from "./AV_BaseTest.t.sol";

contract AV_TradeFacetTest is AV_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenDepositToken_ShouldWork() external {
    vm.prank(ALICE);
    tradeFacet.deposit(address(avShareToken), 10 ether, 0);

    // leverage level is 3
    // price of weth and usdc are 1 USD
    // to calculate borrowed statble token, depositedAmount * leverageLevel - depositedAmount
    // then borrowed stable token is 10 * 3 - 10 = 20
    // to calculate borrowed asset token, depositedAmount * leverageLevel
    // then borrowed asset token is 10 * 3 = 30
    (uint256 _stableDebtValue, uint256 _assetDebtValue) = tradeFacet.getDebtValues(address(avShareToken));
    assertEq(_stableDebtValue, 20 ether);
    assertEq(_assetDebtValue, 30 ether);

    // check liquidty in handler, 30 + 30 / 2 = 30
    assertEq(avHandler.totalLpBalance(), 30 ether);
  }

  function testCorrectness_WhenWithdrawToken_ShouldWork() external {
    vm.startPrank(ALICE);
    tradeFacet.deposit(address(avShareToken), 1 ether, 0);
    tradeFacet.withdraw(address(avShareToken), 1 ether, 0);
    vm.stopPrank();
  }

  // TODO: test management fee to treasury
}
