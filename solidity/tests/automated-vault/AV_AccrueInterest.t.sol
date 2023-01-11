// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { AV_BaseTest, console } from "./AV_BaseTest.t.sol";

// libs
import { LibAV01 } from "../../contracts/automated-vault/libraries/LibAV01.sol";

// mocks
import { MockInterestModel } from "../mocks/MockInterestModel.sol";

contract AV_AccrueInterestTest is AV_BaseTest {
  event LogAccrueInterest(
    address indexed _vaultToken,
    address indexed _stableToken,
    address indexed _assetToken,
    uint256 _stableInterest,
    uint256 _assetInterest
  );

  function setUp() public override {
    super.setUp();

    // address _vaultToken, address _newStableTokenInterestRateModel, address _newAssetTokenInterestRateModel
    adminFacet.setInterestRateModels(
      address(avShareToken),
      address(new MockInterestModel(0.1 ether)),
      address(new MockInterestModel(0.05 ether))
    );

    weth.mint(address(mockRouter), 100 ether);
    usdc.mint(address(mockRouter), 100 ether);
  }

  function testCorrectness_WhenAVDepositSubsequentlyAndTimePast_InterestShouldIncreaseAndAccrued() external {
    /**
     * scenario
     *
     * 0. params
     *    - weth interest rate = 0.05 weth per block
     *    - usdc interest rate = 0.1 usdc per block
     *
     * 1. ALICE deposit 1 usdc at 3x leverage, get 1 vaultToken back
     *    - desired position value = 3 usdc
     *    - weth borrowed = 1.5 weth
     *    - usdc borrowed = 0.5 usdc
     *
     * 2. 1 second pass, interest accrue
     *    - interest = borrowed * ratePerSec
     *    - weth interest = 1.5 * 0.05 = 0.075 weth
     *    - usdc interest = 0.5 * 0.1 = 0.05 usdc
     *
     * 3. BOB deposit 1 usdc at 3x leverage, get 1 vaultToken back
     *    - desired position value = 3 usdc
     *    - weth borrowed = 1.5 weth
     *    - usdc borrowed = 0.5 usdc
     *
     * 4. 1 second pass, interest accrue
     *    - interest = borrowed * ratePerSec
     *    - weth interest = 3 * 0.05 = 0.15 weth
     *    - usdc interest = 1 * 0.1 = 0.1 usdc
     */
    address _vaultToken = address(avShareToken);

    // check last accrue timestamp empty state = 0
    assertEq(viewFacet.getLastAccrueInterestTimestamp(_vaultToken), 0);

    vm.prank(ALICE);
    tradeFacet.deposit(_vaultToken, 1 ether, 0);

    uint256 _stablePendingInterest;
    uint256 _assetPendingInterest;
    // check no pending interest immediately after deposit
    (_stablePendingInterest, _assetPendingInterest) = viewFacet.getPendingInterest(_vaultToken);
    assertEq(_stablePendingInterest, 0);
    assertEq(_assetPendingInterest, 0);

    uint256 _stableDebtValue;
    uint256 _assetDebtValue;
    // check borrowed debt from ALICE
    (_stableDebtValue, _assetDebtValue) = viewFacet.getDebtValues(_vaultToken);
    assertEq(_stableDebtValue, 0.5 ether);
    assertEq(_assetDebtValue, 1.5 ether);

    vm.warp(block.timestamp + 1);

    // check pending interest
    (_stablePendingInterest, _assetPendingInterest) = viewFacet.getPendingInterest(_vaultToken);
    assertEq(_stablePendingInterest, 0.05 ether);
    assertEq(_assetPendingInterest, 0.075 ether);

    vm.prank(BOB);
    tradeFacet.deposit(_vaultToken, 1 ether, 0);

    // check last accrue timestamp = now
    assertEq(viewFacet.getLastAccrueInterestTimestamp(_vaultToken), block.timestamp);

    // check pending interest should = 0 (accrued during BOB deposit)
    (_stablePendingInterest, _assetPendingInterest) = viewFacet.getPendingInterest(_vaultToken);
    assertEq(_stablePendingInterest, 0);
    assertEq(_assetPendingInterest, 0);

    // check borrowed debt from ALICE + BOB + accrued from ALICE
    (_stableDebtValue, _assetDebtValue) = viewFacet.getDebtValues(_vaultToken);
    assertEq(_stableDebtValue, 0.5 ether + 0.5 ether + 0.05 ether);
    assertEq(_assetDebtValue, 1.5 ether + 1.5 ether + 0.075 ether);

    vm.warp(block.timestamp + 1);

    // check last accrue timestamp = last timestamp (no accrual)
    assertEq(viewFacet.getLastAccrueInterestTimestamp(_vaultToken), block.timestamp - 1);

    // check pending interest should accrue based on debt from last time
    (_stablePendingInterest, _assetPendingInterest) = viewFacet.getPendingInterest(_vaultToken);
    assertEq(_stablePendingInterest, 0.105 ether);
    assertEq(_assetPendingInterest, 0.15375 ether);

    // check debt should not changed from last time
    (_stableDebtValue, _assetDebtValue) = viewFacet.getDebtValues(_vaultToken);
    assertEq(_stableDebtValue, 0.5 ether + 0.5 ether + 0.05 ether);
    assertEq(_assetDebtValue, 1.5 ether + 1.5 ether + 0.075 ether);
  }

  function testCorrectness_WhenAVDepositThenWithdraw_ShouldReturnStableAmountWithInterestSubtracted() external {
    /**
     * scenario
     *
     * 0. params
     *    - weth interest rate = 0.05 weth per block
     *    - usdc interest rate = 0.1 usdc per block
     *
     * 1. ALICE deposit 1 usdc at 3x leverage, get 1 vaultToken back
     *    - desired position value = 3 usdc
     *    - weth borrowed = 1.5 weth
     *    - usdc borrowed = 0.5 usdc
     *
     * 2. 1 second pass, interest accrue
     *    - interest = borrowed * ratePerSec
     *    - weth interest = 1.5 * 0.05 = 0.075 weth
     *    - usdc interest = 0.5 * 0.1 = 0.05 usdc
     *
     * 3. ALICE withdraw 1 vaultToken, get 0.875 usdc back
     *    - total interest value = weth interest value + usdc interest value = 0.075 * 1 + 0.05 * 1 = 0.125
     *    - usdc returned = principal - interest = 1 - 0.125 = 0.875 usdc
     *    - withdraw less than deposit because no income, pay interest
     */
    address _vaultToken = address(avShareToken);

    vm.prank(ALICE);
    tradeFacet.deposit(_vaultToken, 1 ether, 0);

    // check no pending interest
    uint256 _stablePendingInterest;
    uint256 _assetPendingInterest;
    (_stablePendingInterest, _assetPendingInterest) = viewFacet.getPendingInterest(_vaultToken);
    assertEq(_stablePendingInterest, 0);
    assertEq(_assetPendingInterest, 0);

    // check debt borrowed
    uint256 _stableDebtValue;
    uint256 _assetDebtValue;
    (_stableDebtValue, _assetDebtValue) = viewFacet.getDebtValues(_vaultToken);
    assertEq(_stableDebtValue, 0.5 ether);
    assertEq(_assetDebtValue, 1.5 ether);

    // check last accrued timestamp = now (accrued during deposit)
    assertEq(viewFacet.getLastAccrueInterestTimestamp(_vaultToken), block.timestamp);

    vm.warp(block.timestamp + 1);

    // check pending interest after time passed should increase
    (_stablePendingInterest, _assetPendingInterest) = viewFacet.getPendingInterest(_vaultToken);
    assertEq(_stablePendingInterest, 0.05 ether);
    assertEq(_assetPendingInterest, 0.075 ether);

    // check last accrued timestamp = previous timestamp (no accrual)
    assertEq(viewFacet.getLastAccrueInterestTimestamp(_vaultToken), block.timestamp - 1);

    mockRouter.setRemoveLiquidityAmountsOut(1.5 ether, 1.5 ether);

    uint256 _aliceUsdcBalanceBefore = usdc.balanceOf(ALICE);

    vm.prank(ALICE);
    tradeFacet.withdraw(_vaultToken, 1 ether, 0, 0);

    // check ALICE's balance
    assertEq(usdc.balanceOf(ALICE) - _aliceUsdcBalanceBefore, 0.875 ether);
    assertEq(avShareToken.balanceOf(ALICE), 0);

    // check no pending interest (accrued during withdraw)
    (_stablePendingInterest, _assetPendingInterest) = viewFacet.getPendingInterest(_vaultToken);
    assertEq(_stablePendingInterest, 0);
    assertEq(_assetPendingInterest, 0);

    // check last accrued timestamp = now (accrued during withdraw)
    assertEq(viewFacet.getLastAccrueInterestTimestamp(_vaultToken), block.timestamp);
  }

  function testCorrectness_WhenMultipleUsersDepositAndWithdraw_EachUserInterestShouldBeAccountedForCorrectly()
    external
  {
    /**
     * scenario
     *
     * 0. params
     *    - weth interest rate = 0.05 weth per block
     *    - usdc interest rate = 0.1 usdc per block
     *
     * 1. ALICE deposit 1 usdc at 3x leverage, get 1 vaultToken back
     *    - desired position value = 3 usdc
     *    - weth borrowed = 1.5 weth
     *    - usdc borrowed = 0.5 usdc
     *
     * 2. BOB deposit 2 usdc at 3x leverage, get 2 vaultToken back
     *    - desired position value = 6 usdc
     *    - weth borrowed = 3 weth
     *    - usdc borrowed = 1 usdc
     *
     * 3. 1 second pass, pending interest increase
     *    - pending weth = 4.5 * 0.05 = 0.225 weth
     *      - ALICE portion = 0.075
     *      - BOB portion = 0.15
     *    - pending usdc = 1.5 * 0/1 = 0.15 usdc
     *      - ALICE portion = 0.05
     *      - BOB portion = 0.1
     *
     * 4. ALICE withdraw 1 vaultToken, get back 0.875 usdc
     *    - interest accrued
     *      - new weth debt = 4.5 + 0.225 = 4.725 weth
     *      - new usdc debt = 1.5 + 0.15 = 1.65 usdc
     *    - no change in lp, withdraw 1.5 usdc, 1.5 weth from handler
     *    - repay weth = 1.5 + 0.075 = 1.575 weth
     *    - repay usdc = 0.5 + 0.05 = 0.55 usdc
     *    - get usdc back = principal - weth and usdc interest = 1 - (0.075 + 0.05) = 0.875 usdc
     *
     * 5. BOB withdraw 1 vaultToken, get back 1.75 usdc
     *    - no interest accrual
     *    - no change in lp, withdraw 3 usdc, 3 weth from handler
     *    - repay weth = 3 + 0.15 = 3.15 weth
     *    - repay usdc = 1 + 0.1 = 1.1 usdc
     *    - get usdc back = principal - weth and usdc interest = 2 - (0.15 + 0.1) = 1.75 usdc
     */

    address _vaultToken = address(avShareToken);

    // 1.
    vm.prank(ALICE);
    tradeFacet.deposit(_vaultToken, 1 ether, 0);
    // 2.
    vm.prank(BOB);
    tradeFacet.deposit(_vaultToken, 2 ether, 0);

    // 3.
    vm.warp(block.timestamp + 1);

    // 4.
    mockRouter.setRemoveLiquidityAmountsOut(1.5 ether, 1.5 ether);
    uint256 _aliceUsdcBalanceBefore = usdc.balanceOf(ALICE);
    vm.prank(ALICE);
    tradeFacet.withdraw(_vaultToken, 1 ether, 0, 0);

    // check ALICE
    (uint256 _stableDebtValue, uint256 _assetDebtValue) = viewFacet.getDebtValues(_vaultToken);
    assertEq(_stableDebtValue, 1.65 ether - 0.55 ether);
    assertEq(_assetDebtValue, 4.725 ether - 1.575 ether);
    assertEq(usdc.balanceOf(ALICE) - _aliceUsdcBalanceBefore, 0.875 ether);

    // 5.
    mockRouter.setRemoveLiquidityAmountsOut(3 ether, 3 ether);
    // uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);
    vm.prank(BOB);
    tradeFacet.withdraw(_vaultToken, 2 ether, 0, 0);

    // check BOB
    (_stableDebtValue, _assetDebtValue) = viewFacet.getDebtValues(_vaultToken);
    assertEq(_stableDebtValue, 0);
    assertEq(_assetDebtValue, 0);
    // TODO: handle surplus usdc left in vault
    // assertEq(usdc.balanceOf(BOB) - _bobUsdcBalanceBefore, 1.75 ether);
  }

  function testCorrectness_WhenDepositThenLPPriceDropThenWithdraw_ProtocolShouldProfitFromInterest() external {
    /**
     * scenario
     *
     * 0. starting condition
     *    - usdc price = 1 usd, weth price = 1 usd
     *    - usdc interest = 0.1 usdc per 1 usdc borrowed per second
     *    - weth interest = 0.05 weth per 1 weth borrowed per second
     *
     * 1. ALICE deposit 1 ether, get 1 vaultToken back
     *    - borrow 0.5 usdc
     *    - borrow 1.5 weth
     *
     * 2. 1 second pass, pending interest increase
     *    - pending 0.05 usdc
     *    - pending 0.075 weth
     *
     * 3. weth price drops to 0.5 usdc / weth, lp is affected
     *    - initial lp has 1.5 usdc, 1.5 weth, lp usd value = 3 usd
     *    - since weth price drop by half, lp composition change to 1 usdc, 2 weth
     *    - lp usd value after = 2 usd
     *
     * 4. ALICE withdraw 1 vaultToken
     *    - interest accrued, debt increase
     *      - usdc debt = 0.55 usdc
     *      - weth debt = 1.575 weth
     *    - withdraw from handler, get back 1 usdc, 2 weth
     *    - repay usdc av debt 0.55 usdc
     *    - repay weth av debt 1.575 weth
     *    - equity = totalLPValue - debt = 2 - (0.55 * 1 + 1.575 * 0.5) = 0.6625 usd
     *    - ALICE get `returned from lp - repaid` back, total value = equity = 0.6625 usd
     *      - 1 - 0.55 = 0.45 usdc
     *      - 2 - 1.575 = 0.425 weth
     *
     * 5. vault end state
     *    - usdc av accounting debt = 0
     *    - weth av accounting debt = 0
     *    - physical usdc left = 1 - 0.45 = 0.55 usdc
     *    - physical weth left = 2 - 0.425 = 1.575 weth
     *    - usdc mm debt = 0.5 usdc
     *    - weth mm debt = 1.5 weth
     *    - usdc profit after clear mm debt = 0.55 - 0.5 = 0.05 usdc
     *    - weth profit after clear mm debt = 1.575 - 1.5 = 0.075 weth
     */

    address _vaultToken = address(avShareToken);

    // 1.
    vm.prank(ALICE);
    tradeFacet.deposit(_vaultToken, 1 ether, 0);

    // 2.
    vm.warp(block.timestamp + 1);

    // 3.
    mockRouter.setRemoveLiquidityAmountsOut(2 ether, 1 ether); // (weth, usdc)

    // 4.
    uint256 _aliceUsdcBalanceBefore = usdc.balanceOf(ALICE);
    uint256 _aliceWethBalanceBefore = weth.balanceOf(ALICE);

    vm.prank(ALICE);
    tradeFacet.withdraw(_vaultToken, 1 ether, 0, 0);

    // check ALICE state
    assertEq(usdc.balanceOf(ALICE) - _aliceUsdcBalanceBefore, 0.45 ether);
    assertEq(weth.balanceOf(ALICE) - _aliceWethBalanceBefore, 0.425 ether);

    // check vault state
    assertEq(usdc.balanceOf(avDiamond), 0.55 ether);
    assertEq(weth.balanceOf(avDiamond), 1.575 ether);
    (uint256 _usdcDebt, uint256 _wethDebt) = viewFacet.getDebtValues(_vaultToken);
    assertEq(_usdcDebt, 0);
    assertEq(_wethDebt, 0);
  }

  function testCorrectness_WhenAccrueInterest_ShouldEmitEvent() external {
    address _vaultToken = address(avShareToken);

    vm.expectEmit(true, true, true, false, avDiamond);
    emit LogAccrueInterest(_vaultToken, address(usdc), address(weth), 0, 0);
    vm.prank(ALICE);
    tradeFacet.deposit(_vaultToken, 1 ether, 0);

    vm.warp(block.timestamp + 1);

    mockRouter.setRemoveLiquidityAmountsOut(1.5 ether, 1.5 ether);

    vm.expectEmit(true, true, true, false, avDiamond);
    emit LogAccrueInterest(_vaultToken, address(usdc), address(weth), 0.05 ether, 0.075 ether);
    vm.prank(ALICE);
    tradeFacet.withdraw(_vaultToken, 1 ether, 0, 0);
  }
}
