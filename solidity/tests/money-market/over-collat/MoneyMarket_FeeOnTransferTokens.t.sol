// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, console } from "../MoneyMarket_BaseTest.t.sol";

import { FixedFeeModel } from "../../../contracts/money-market/fee-models/FixedFeeModel.sol";

// libs
import { LibMoneyMarket01 } from "../../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// mocks
import { MockFeeOnTransferToken } from "../../mocks/MockFeeOnTransferToken.sol";

// helpers
import { TestHelper } from "../../helper/TestHelper.sol";

contract MoneyMarket_FeeOnTransferTokensTest is MoneyMarket_BaseTest {
  MockFeeOnTransferToken internal fotToken;
  MockFeeOnTransferToken internal lateFotToken;

  function setUp() public override {
    super.setUp();

    fotToken = new MockFeeOnTransferToken("Fee on transfer", "FOT", 18, 100);
    lateFotToken = new MockFeeOnTransferToken("Fee on transfer", "FOT", 18, 0);

    fotToken.mint(ALICE, 100 ether);
    lateFotToken.mint(ALICE, 100 ether);

    vm.startPrank(ALICE);
    fotToken.approve(moneyMarketDiamond, type(uint256).max);
    lateFotToken.approve(moneyMarketDiamond, type(uint256).max);
    lateFotToken.approve(address(accountManager), type(uint256).max);
    vm.stopPrank();

    fotToken.mint(BOB, 100 ether);
    lateFotToken.mint(BOB, 100 ether);

    vm.startPrank(BOB);
    fotToken.approve(moneyMarketDiamond, type(uint256).max);
    lateFotToken.approve(moneyMarketDiamond, type(uint256).max);
    lateFotToken.approve(address(accountManager), type(uint256).max);
    vm.stopPrank();

    TestHelper.openMarketWithDefaultTokenConfig(moneyMarketDiamond, address(fotToken));
    TestHelper.openMarketWithDefaultTokenConfig(moneyMarketDiamond, address(lateFotToken));

    mockOracle.setTokenPrice(address(fotToken), 1 ether);
    mockOracle.setTokenPrice(address(lateFotToken), 1 ether);

    // setup fotToken that can be borrowed
    vm.startPrank(ALICE);

    accountManager.deposit(address(lateFotToken), 10 ether);
    vm.stopPrank();

    lateFotToken.setFee(100);

    // set repurchase fee model
    FixedFeeModel fixedFeeModel = new FixedFeeModel();
    adminFacet.setRepurchaseRewardModel(fixedFeeModel);
  }

  function testRevert_WhenDepositWithFeeOnTransferToken() external {
    // inject token to account manager first, trying to bypass exceed balance error at MM
    fotToken.mint(address(accountManager), 1 ether);

    vm.startPrank(BOB);

    fotToken.approve(address(accountManager), type(uint256).max);
    vm.expectRevert(LibMoneyMarket01.LibMoneyMarket01_FeeOnTransferTokensNotSupported.selector);
    accountManager.deposit(address(fotToken), 1 ether);
    vm.stopPrank();
  }

  function testRevert_WhenAddCollateralWithFeeOnTransferToken() external {
    // inject token to account manager first, trying to bypass exceed balance error at MM
    fotToken.mint(address(accountManager), 1 ether);

    vm.startPrank(BOB);

    fotToken.approve(address(accountManager), type(uint256).max);
    vm.expectRevert(LibMoneyMarket01.LibMoneyMarket01_FeeOnTransferTokensNotSupported.selector);
    accountManager.addCollateralFor(BOB, subAccount0, address(fotToken), 1 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenBorrowFeeOnTransferToken_ShouldAbleToBorrowButReceiveAmountAfterFee() external {
    uint256 _borrowAmount = 1 ether;

    uint256 _bobBalanceBefore = lateFotToken.balanceOf(BOB);
    // inject directly to account manager to bypass !safeTransfer at account manager
    lateFotToken.mint(address(accountManager), 1 ether);

    vm.startPrank(BOB);
    accountManager.addCollateralFor(BOB, subAccount0, address(weth), 10 ether);
    accountManager.borrow(subAccount0, address(lateFotToken), _borrowAmount);
    vm.stopPrank();

    // after borrow should receive _borrowAmount - _transferFee
    uint256 _transferFee = (_borrowAmount * lateFotToken.transferFeeBps()) / 10000;
    assertEq(lateFotToken.balanceOf(BOB) - _bobBalanceBefore, _borrowAmount - _transferFee);

    // debt should be accounted for full _borrowAmount before fee
    (, uint256 _debtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(BOB, subAccount0, address(lateFotToken));
    assertEq(_debtAmount, _borrowAmount);
  }

  function testCorrectness_WhenRepayFeeOnTransferTokenDebt_ShouldBeAbleToRepayButDebtReducedWithAmountAfterFee()
    external
  {
    uint256 _borrowAmount = 1 ether;

    // turn off minDebtSize because it will cause repay full amount to fail due to fee being taken and
    // small debt is left after repayment
    adminFacet.setMinDebtSize(0);

    // inject directly to account manager to bypass !safeTransfer at account manager
    lateFotToken.mint(address(accountManager), 10 ether);

    vm.startPrank(BOB);
    accountManager.addCollateralFor(BOB, subAccount0, address(weth), 10 ether);
    accountManager.borrow(subAccount0, address(lateFotToken), _borrowAmount);
    accountManager.repayFor(BOB, subAccount0, address(lateFotToken), 10 ether, _borrowAmount);
    vm.stopPrank();

    // BOB is left with _feeAmount short of starting point because _feeAmount is taken during borrow
    // due to the fact that token were transfer back and forth at account manager
    // BOB got < 100 + 0.99 (subjected to fee during borrow) - 1 (repay) - (fee on transfer during repay)
    // fee on transfer during repay = 10 * 0.99 = 9.99, transfer to repay 1 ether
    // 8.9 left to transfer back => 8.9 * 0.99 = 8.811
    // total left = 100 + 0.99 -10  + 8.811 => 99.801
    assertEq(lateFotToken.balanceOf(BOB), 99.801000000000000000 ether);

    // can't repay entire debt because transfer fee during repayment is deduced
    uint256 _feeAmount = (_borrowAmount * (lateFotToken.transferFeeBps())) / 10000;
    (, uint256 _debtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(BOB, subAccount0, address(lateFotToken));
    assertEq(_debtAmount, _feeAmount);
  }

  function testCorrectness_WhenRepurchaseFeeOnTransferToken_ShouldBeAbleRepurchaseButDebtReducedWithAmountAfterFee()
    external
  {
    address _debtToken = address(lateFotToken);
    address _collatToken = address(weth);
    uint256 _repurchaseAmount = 0.1 ether;

    uint256 _treasuryBalanceBefore = lateFotToken.balanceOf(liquidationTreasury);
    uint256 _aliceWethBalanceBefore = weth.balanceOf(ALICE);

    // inject directly to account manager to bypass !safeTransfer at account manager
    lateFotToken.mint(address(accountManager), 10 ether);

    vm.startPrank(BOB);
    accountManager.addCollateralFor(BOB, subAccount0, _collatToken, 2 ether);
    accountManager.borrow(subAccount0, _debtToken, 1 ether);
    vm.stopPrank();

    mockOracle.setTokenPrice(_collatToken, 0.5 ether);

    (, uint256 _debtAmountBefore) = viewFacet.getOverCollatDebtShareAndAmountOf(BOB, subAccount0, _debtToken);

    vm.prank(ALICE, ALICE);
    liquidationFacet.repurchase(BOB, subAccount0, _debtToken, _collatToken, _repurchaseAmount);

    // check ALICE weth collat receieved + repurchaseReward
    // collat payout = 0.1 / 0.5 = 0.2 weth, reward = 0.2 * 0.01 = 0.002 weth
    assertEq(weth.balanceOf(ALICE) - _aliceWethBalanceBefore, 0.202 ether);

    // repurchaseFee = 1%, transferFee = 1%
    // repaid = desiredRepay / (1 + repurchaseFeePct)
    //        = 0.1 / (1 + 0.01)
    // check debt reduced = repaid - transferFee
    //                    = repaid - (desiredRepay * transferFeePct)
    //                    = (0.1 / (1 + 0.01)) - (0.1 * 0.01) = 0.098009900990099009
    (, uint256 _debtAmountAfter) = viewFacet.getOverCollatDebtShareAndAmountOf(BOB, subAccount0, _debtToken);
    assertEq(_debtAmountBefore - _debtAmountAfter, 0.098009900990099009 ether);

    // check fee to treasury = repurchaseFee - transferFee
    //                       = repaid * repurchaseFeePct * (1 - transferFeePct)
    //                       = 0.1 / (1 + 0.01) * 0.01 * (1 - 0.01) = 0.000980198019801982
    assertEq(lateFotToken.balanceOf(liquidationTreasury) - _treasuryBalanceBefore, 0.000980198019801982 ether);
  }
}
