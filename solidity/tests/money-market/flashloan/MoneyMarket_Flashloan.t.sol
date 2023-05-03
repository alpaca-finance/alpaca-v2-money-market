// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest, console } from "../MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../../contracts/money-market/libraries/LibMoneyMarket01.sol";
import { LibConstant } from "../../../contracts/money-market/libraries/LibConstant.sol";
import { LibReentrancyGuard } from "../../../contracts/money-market/libraries/LibReentrancyGuard.sol";

// interfaces
import { IFlashloanFacet } from "../../../contracts/money-market/interfaces/IFlashloanFacet.sol";
import { IERC20 } from "../../../contracts/money-market/interfaces/IERC20.sol";

// mock
import { MockFlashloan } from "./MockFlashloan.sol";
import { MockFlashloan_Redeposit } from "./MockFlashloan_Redeposit.sol";

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

  // NOTE: if token is not available in pool.
  // It will revert same as "no liquidity" or "ERC20: transfer amount exceeds balance"

  function testCorrectness_WhenUserCallFlashloan_ShouldWork() external {
    // flashloan 1 usdc
    uint256 _flashloanAmount = normalizeEther(1 ether, usdcDecimal);

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
    // fee = 0.05 USDC
    // reserve = 10 + 0.05 = 10.05 USDC
    // protocol reserve = 0.025 USDC
    // total token = 10.05 - 0.025 = 10.025 USDC

    // call flashloan with 1 usdc
    mockFlashloan.flash(address(usdc), _flashloanAmount, "");

    // mock flashloan contract should have 5 - (1 * fee) =  4.95 usdc
    uint256 _mockFlashloanBalanceAfter = usdc.balanceOf(address(mockFlashloan));

    //  - user balance is deducted correctly
    assertEq(_mockFlashloanBalanceAfter, normalizeEther(4.95 ether, usdcDecimal), "mockFlashloan USDC balance");

    //  - reserve increase correctly
    uint256 _reserve = viewFacet.getFloatingBalance(address(usdc));
    assertEq(_reserve, normalizeEther(10.05 ether, usdcDecimal), "Reserve");

    // - protocol reserve increase correctly
    // 0 -> 0.025
    uint256 _protocolReserve = viewFacet.getProtocolReserve(address(usdc));
    assertEq(_protocolReserve, normalizeEther(0.025 ether, usdcDecimal), "Protocol reserve");
  }

  // test if repay excess the expected fee (should work)
  function testCorrectness_WhenContractRepayGreaterThanExpectedFee_ShouldWork() external {
    // define flashloan amount
    uint256 _flashloanAmount = normalizeEther(1 ether, usdcDecimal);

    // define data for use as extra fee
    bytes memory _data = abi.encode(true, normalizeEther(1 ether, usdcDecimal));

    // call flashloan with 1 usdc with extra fee (1 usdc)
    mockFlashloan.flash(address(usdc), _flashloanAmount, _data);

    // check contract
    uint256 _mockFlashloanBalanceAfter = usdc.balanceOf(address(mockFlashloan));

    // Contract should have 5 - (1 * fee) - 1 (extra fee) =  3.95 usdc
    assertEq(_mockFlashloanBalanceAfter, normalizeEther(3.95 ether, usdcDecimal));

    // check reserve
    // Reserve = 10 USDC
    // fee = 0.05 USDC
    // After flash, reserve = current + fee + extra
    // 10 + 0.05 + 1 = 11.05 USDC #
    // Extra 1 USDC should go to protocol reserve
    // protocol reserve = current + fee + extra = 0 + 0.025 + 1 = 1.025 USDC #
    uint256 _reserve = viewFacet.getFloatingBalance(address(usdc));
    assertEq(_reserve, normalizeEther(11.05 ether, usdcDecimal), "Reserve");

    uint256 _protocolReserve = viewFacet.getProtocolReserve(address(usdc));
    assertEq(_protocolReserve, normalizeEther(1.025 ether, usdcDecimal), "Protocol reserve");
  }

  // test if repay less than the expected fee (should revert)
  function testRevert_WhenContractRepayLessThanExpectedFee_ShouldRevert() external {
    uint256 _flashloanAmount = normalizeEther(1 ether, usdcDecimal);
    bytes memory _data = abi.encode(false, normalizeEther(0.01 ether, usdcDecimal));

    // call flashloan with 1 USDC with -0.01 USDC fee
    vm.expectRevert(abi.encodeWithSelector(IFlashloanFacet.FlashloanFacet_NotEnoughRepay.selector));
    mockFlashloan.flash(address(usdc), _flashloanAmount, _data);
  }

  // test if loan amount is bigger than reserve
  function testRevert_WhenLoanAmountIsBiggerThanReserve_ShouldRevert() external {
    // reserve = 10 USDC
    // loan = 11 USDC
    uint256 _flashloanAmount = normalizeEther(11 ether, usdcDecimal);

    // call flashloan with 11 usdc
    // in detail, should revert "ERC20: transfer amount exceeds balance". But we use safeTransfer Lib
    vm.expectRevert("!safeTransfer");
    mockFlashloan.flash(address(usdc), _flashloanAmount, "");
  }

  // Flash and deposit back to mm, should revert with Reentrant error
  // deposit direct to mm
  // deposit with account manager
  function testRevert_WhenContractCallFlashloanAndDepositBacktoMM_ShouldRevert() external {
    // mock flashloan have: 5 USDC
    // reserve and balanceOf(mm): 10 USDC

    // flashloan all balance
    uint256 _flashloanAmount = usdc.balanceOf(moneyMarketDiamond);

    // mock new flashloan that implements redeposit
    MockFlashloan_Redeposit _mockRedepositFlashloan = new MockFlashloan_Redeposit(moneyMarketDiamond);
    usdc.mint(address(_mockRedepositFlashloan), normalizeEther(5 ether, usdcDecimal));

    // deposit back to mm
    // - direct, should revert LibReentrancyGuard_ReentrantCall before LibMoneyMarket01_UnAuthorized
    {
      vm.expectRevert(LibReentrancyGuard.LibReentrancyGuard_ReentrantCall.selector);
      _mockRedepositFlashloan.flash(address(usdc), _flashloanAmount, "");
    }
    // - via account manager, should revert LibReentrancyGuard_ReentrantCall
    {
      bytes memory _data = abi.encode(address(accountManager), _flashloanAmount);
      vm.expectRevert(LibReentrancyGuard.LibReentrancyGuard_ReentrantCall.selector);
      _mockRedepositFlashloan.flash(address(usdc), _flashloanAmount, _data);
    }
  }

  // Flash and repurchase, should revert with Reentrant error
  function testRevert_WhenContractCallFlashloanAndRepurchase_ShouldRevert() external {}

  // Flash and withdraw
}
