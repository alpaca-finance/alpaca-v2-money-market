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
    // uint256 _AliceBalanceBefore = usdc.balanceOf(ALICE);
    uint256 _flashloanAmount = normalizeEther(1 ether, usdcDecimal);
    (, , , uint16 _flashloanFee) = viewFacet.getFeeParams();

    uint256 _expectedFee = (_flashloanAmount * _flashloanFee) / LibConstant.MAX_BPS;

    uint256 _reserveBefore = viewFacet.getTotalToken(address(usdc));

    // deposit to
    vm.startPrank(ALICE);
    usdc.transfer(address(mockFlashloan), _flashloanAmount * 3);
    vm.stopPrank();

    uint256 _mockFlashloanBalanceBefore = usdc.balanceOf(address(mockFlashloan));

    vm.startPrank(address(mockFlashloan));
    mockFlashloan.flash(moneyMarketDiamond, address(usdc), _flashloanAmount);
    vm.stopPrank();
    // uint256 _AliceBalanceAfter = usdc.balanceOf(ALICE);
    uint256 _mockFlashloanBalanceAfter = usdc.balanceOf(address(mockFlashloan));

    //  - user balance is deducted correctly
    assertLt(_mockFlashloanBalanceAfter, _mockFlashloanBalanceBefore, "mockFlashloan USDC balance");

    //  - reserve increase correctly
    uint256 _reserveAfter = viewFacet.getTotalToken(address(usdc));
    // assertEq(_reserveAfter, _reserveBefore + _expectedFee, "Reserve");
  }

  // test if repay excess the expected fee (should work)
  function testCorrectness_WhenUserRepayGreaterThanExpectedFee_ShouldWork() external {}

  // test if repay less than the expected fee (should revert)
  function testRevert_WhenUserRepayLessThanExpectedFee_ShouldRevert() external {}

  // test if token is not available for flashloan (should revert)
  function testRevert_WhenUserFlashloanOnNonExistingToken_ShouldRevert() external {}
}
