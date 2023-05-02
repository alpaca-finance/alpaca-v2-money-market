// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest, console } from "../MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { ILendFacet } from "../../../contracts/money-market/interfaces/ILendFacet.sol";
import { IERC20 } from "../../../contracts/money-market/interfaces/IERC20.sol";

// mock
import { MockFlashloan } from "./MockFlashloan.sol";

contract MoneyMarket_Flashloan is MoneyMarket_BaseTest {
  MockFlashloan internal mockFlashloan;

  function setUp() public override {
    super.setUp();

    // pool must have reserve

    mockFlashloan = new MockFlashloan();

    // usdc.mint(moneyMarketDiamond, normalizeEther(1000 ether, usdcDecimal));
    vm.prank(ALICE);
    uint256 _depositAmount = normalizeEther(10 ether, usdcDecimal);
    accountManager.deposit(address(usdc), _depositAmount);
  }

  // test flashloan work correctly
  //  - user balance is deducted correctly
  //  - reserve increase correctly
  //  - protocol reserve increase correctly
  function testCorrectness_WhenUserCallFlashloan_ShouldWork() external {
    uint256 _AliceBalanceBefore = usdc.balanceOf(ALICE);
    uint256 _flashloanAmount = normalizeEther(1 ether, usdcDecimal);

    // deposit to
    vm.startPrank(ALICE);
    usdc.transfer(address(mockFlashloan), _flashloanAmount * 3);
    vm.stopPrank();

    vm.startPrank(address(mockFlashloan));
    mockFlashloan.flash(moneyMarketDiamond, address(usdc), _flashloanAmount);
    vm.stopPrank();
    uint256 _AliceBalanceAfter = usdc.balanceOf(ALICE);

    assertLt(_AliceBalanceAfter, _AliceBalanceBefore, "ALICE USDC balance");
  }

  // test if repay excess the expected fee (should work)
  function testCorrectness_WhenUserRepayGreaterThanExpectedFee_ShouldWork() external {}

  // test if repay less than the expected fee (should revert)
  function testRevert_WhenUserRepayLessThanExpectedFee_ShouldRevert() external {}

  // test if token is not available for flashloan (should revert)
  function testRevert_WhenUserFlashloanOnNonExistingToken_ShouldRevert() external {}
}
