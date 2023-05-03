// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest, console } from "../MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../../contracts/money-market/libraries/LibMoneyMarket01.sol";
import { LibConstant } from "../../../contracts/money-market/libraries/LibConstant.sol";

// interfaces
import { ILendFacet } from "../../../contracts/money-market/interfaces/ILendFacet.sol";
import { IERC20 } from "../../../contracts/money-market/interfaces/IERC20.sol";

// mock
import { MockFlashloan } from "./MockFlashloan.sol";

contract MoneyMarket_Flashloan is MoneyMarket_BaseTest {
  MockFlashloan internal mockFlashloan;

  function setUp() public override {
    super.setUp();

    mockFlashloan = new MockFlashloan(moneyMarketDiamond);
    // add 5 usdc to mock flashloan contract
    usdc.mint(address(mockFlashloan), normalizeEther(5 ether, usdcDecimal));

    // add 10 USDC to moneymarket's reserve
    vm.prank(ALICE);
    uint256 _depositAmount = normalizeEther(10 ether, usdcDecimal);
    accountManager.deposit(address(usdc), _depositAmount);
  }

  // test flashloan work correctly
  //  - user balance is deducted correctly
  //  - reserve increase correctly
  //  - protocol reserve increase correctly
  function testCorrectness_WhenUserCallFlashloan_ShouldWork() external {
    // Fee calculation:
    // =============================
    // fee = 5% of amount
    // flashloan amount: 1 USDC
    // fee = 1 USDC * 5% = 0.05 USDC
    // Contract: 5 USDC
    // After call flashloan = balance - fee from flashloan
    // = 5 - (1 * 5%) = 4.95 USDC

    // Reserve calculation:
    // =============================
    // Market reserve: 10 USDC
    // After call flashloan, reserve = current reserve + (50% of fee from flashloan's amount)
    // reserve = 10 + (1 * 5%/2) = 10 + (0.05/2) = 10.025 USDC
    // protocol reserve = 0.025 USDC

    // flashloan 1 usdc
    uint256 _flashloanAmount = normalizeEther(1 ether, usdcDecimal);

    // call flashloan with 1 usdc
    vm.startPrank(address(mockFlashloan));
    mockFlashloan.flash(address(usdc), _flashloanAmount, "");
    vm.stopPrank();

    // mock flashloan contract should have 5 - (1 * fee) =  4.95 usdc
    uint256 _mockFlashloanBalanceAfter = usdc.balanceOf(address(mockFlashloan));

    //  - user balance is deducted correctly
    assertEq(_mockFlashloanBalanceAfter, normalizeEther(4.95 ether, usdcDecimal), "mockFlashloan USDC balance");

    //  - reserve increase correctly
    uint256 _reserveAfter = viewFacet.getTotalToken(address(usdc));
    assertEq(_reserveAfter, normalizeEther(10.025 ether, usdcDecimal), "Reserve");
  }

  // test if repay excess the expected fee (should work)
  function testCorrectness_WhenContractRepayGreaterThanExpectedFee_ShouldWork() external {}

  // test if repay less than the expected fee (should revert)
  function testRevert_WhenContractRepayLessThanExpectedFee_ShouldRevert() external {}

  // test if token is not available for flashloan (should revert)
  function testRevert_WhenContractCallFlashloanOnNonExistingToken_ShouldRevert() external {}

  // Flash and deposit back to mm, should revert with Reentrant error
  function testRevert_WhenContractCallFlashloanAndDepositBacktoMM_ShouldRevert() external {}

  // Flash and repurchase, should revert with Reentrant error
  function testRevert_WhenContractCallFlashloanAndRepurchase_ShouldRevert() external {}
}
