// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, console } from "./LYF_BaseTest.t.sol";

// interfaces
import { ILYFLiquidationFacet } from "../../contracts/lyf/interfaces/ILYFLiquidationFacet.sol";
import { IMoneyMarket } from "../../contracts/lyf/interfaces/IMoneyMarket.sol";

// mocks
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockLiquidationStrategy } from "../mocks/MockLiquidationStrategy.sol";

// libraries
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";

contract LYF_LiquidationFacetTest is LYF_BaseTest {
  uint256 _subAccountId = 0;
  address _aliceSubAccount0 = LibLYF01.getSubAccount(ALICE, _subAccountId);
  MockLiquidationStrategy internal mockLiquidationStrategy;
  address constant liquidator = address(1000);

  uint256 constant REPURCHASE_REWARD_BPS = 100;
  uint256 constant REPURCHASE_FEE_BPS = 100;

  function setUp() public override {
    super.setUp();

    mockLiquidationStrategy = new MockLiquidationStrategy(address(mockOracle));

    address[] memory _liquidationStrats = new address[](1);
    _liquidationStrats[0] = address(mockLiquidationStrategy);
    adminFacet.setLiquidationStratsOk(_liquidationStrats, true);

    address[] memory _liquidators = new address[](1);
    _liquidators[0] = address(liquidator);
    adminFacet.setLiquidationCallersOk(_liquidators, true);

    usdc.mint(address(mockLiquidationStrategy), 1000 ether);

    vm.prank(liquidator);
    usdc.approve(lyfDiamond, type(uint256).max);
  }

  function _calcCollatRepurchaserShouldReceive(uint256 debtToRepurchase, uint256 collatUSDPrice)
    internal
    pure
    returns (uint256 result)
  {
    result = (debtToRepurchase * (10000 + REPURCHASE_FEE_BPS) * 1e14) / collatUSDPrice;
  }

  function testCorrectness_WhenPartialRepurchase_ShouldWork() external {
    /**
     * scenario:
     *
     * 1. @ 1 usdc/weth: alice add collateral 40 weth, open farm with 30 weth, 30 usdc
     *      - 30 weth collateral is used to open position -> 10 weth left as collateral
     *      - alice need to borrow 30 usdc
     *      - alice total borrowing power = (10 * 1 * 0.9) + (30 * 2 * 0.9) = 63 usd
     *
     * 2. lp price drops to 0.5 usdc/lp -> position become repurchaseable
     *      - alice total borrowing power = (10 * 1 * 0.9) + (30 * 0.5 * 0.9) = 22.5 usd
     *
     * 3. bob repurchase weth collateral with 5 usdc, bob will receive 5.05 weth
     *      - 5 / 1 = 5 weth will be repurchased by bob
     *      - 5 * 1% = 0.05 weth as repurchase reward for bob
     *
     * 4. alice position after repurchase
     *      - alice subaccount 0: weth collateral = 10 - 5.05 = 4.95 weth
     *      - alice subaccount 0: usdc debt = 30 - 5 = 25 usdc
     */
    address _collatToken = address(weth);
    address _debtToken = address(usdc);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _amountToRepurchase = 5 ether;

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 40 ether);
    farmFacet.addFarmPosition(subAccount0, _lpToken, 30 ether, 30 ether, 0);
    vm.stopPrank();

    uint256 _bobWethBalanceBefore = weth.balanceOf(BOB);
    uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);

    mockOracle.setTokenPrice(address(_lpToken), 0.5 ether);

    vm.prank(BOB);
    liquidationFacet.repurchase(ALICE, subAccount0, _debtToken, _collatToken, _lpToken, _amountToRepurchase, 0);

    // check bob balance
    uint256 _wethReceivedFromRepurchase = _calcCollatRepurchaserShouldReceive(_amountToRepurchase, 1 ether);
    assertEq(weth.balanceOf(BOB) - _bobWethBalanceBefore, _wethReceivedFromRepurchase);
    assertEq(_bobUsdcBalanceBefore - usdc.balanceOf(BOB), _amountToRepurchase);

    // check alice position
    assertEq(
      collateralFacet.subAccountCollatAmount(_aliceSubAccount0, _collatToken),
      10 ether - _wethReceivedFromRepurchase // TODO: account for repurchase fee
    );
    (, uint256 _aliceUsdcDebtValue) = farmFacet.getDebt(ALICE, subAccount0, address(usdc), _lpToken);
    assertEq(_aliceUsdcDebtValue, 25 ether);
  }

  function testCorrectness_WhenRepurchaseMoreThanDebt_ShouldRepurchaseAllDebtOnThatToken() external {
    /**
     * scenario:
     *
     * 1. @ 10 usdc/btc, 1 usdc/weth: alice add collateral 4 btc, open farm with 30 weth, 30 usdc
     *      - alice need to borrow 30 usdc, 30 weth -> borrowed value = 60 usd
     *
     * 2. lp price drops to 0.5 usdc/lp -> position become repurchaseable
     *      - alice total borrowing power = (10 * 4 * 0.9) + (30 * 0.5 * 0.9) = 49.5 usd
     *
     * 3. bob repurchase btc collateral with 40 usdc -> capped at 30 usdc, bob will receive 3.03 btc
     *      - 30 / 10 = 3 btc will be repurchased by bob
     *      - 3 * 1% = 0.03 btc as repurchase reward for bob
     *
     * 4. alice position after repurchase
     *      - alice subaccount 0: btc collateral = 4 - 3.03 = 0.97 btc
     *      - alice subaccount 0: usdc debt = 30 - 30 = 0 usdc
     *      - alice subaccount 0: weth debt = 30 weth unchanged
     */
    address _collatToken = address(btc);
    address _debtToken = address(usdc);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _amountToRepurchase = 40 ether;

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 4 ether);
    farmFacet.addFarmPosition(subAccount0, _lpToken, 30 ether, 30 ether, 0);
    vm.stopPrank();

    uint256 _bobBtcBalanceBefore = btc.balanceOf(BOB);
    uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);

    mockOracle.setTokenPrice(address(_lpToken), 0.5 ether);

    vm.prank(BOB);
    liquidationFacet.repurchase(ALICE, subAccount0, _debtToken, _collatToken, _lpToken, _amountToRepurchase, 0);

    // check bob balance
    uint256 _actualRepurchase = 30 ether;
    uint256 _btcReceivedFromRepurchase = _calcCollatRepurchaserShouldReceive(_actualRepurchase, 10 ether);
    assertEq(btc.balanceOf(BOB) - _bobBtcBalanceBefore, _btcReceivedFromRepurchase);
    assertEq(_bobUsdcBalanceBefore - usdc.balanceOf(BOB), _actualRepurchase);

    // check alice position
    assertEq(
      collateralFacet.subAccountCollatAmount(_aliceSubAccount0, _collatToken),
      4 ether - _btcReceivedFromRepurchase // TODO: account for repurchase fee
    );
    (, uint256 _aliceUsdcDebtValue) = farmFacet.getDebt(ALICE, subAccount0, address(usdc), _lpToken);
    assertEq(_aliceUsdcDebtValue, 0);
    (, uint256 _aliceWethDebtValue) = farmFacet.getDebt(ALICE, subAccount0, address(weth), _lpToken);
    assertEq(_aliceWethDebtValue, 30 ether);
  }

  function testCorrectness_WhenPartialRepurchaseIb_ShouldWork() external {
    /**
     * scenario:
     *
     * 1. @ 1 usdc/weth, 1.2 weth/ibWeth: alice add collateral 40 ibWeth, open farm with 30 weth, 30 usdc
     *      - 30 / 1.2 = 25 ibWeth collateral is redeemed for 30 weth to open position -> 15 ibWeth left as collateral
     *      - alice need to borrow 30 usdc
     *      - alice total borrowing power = (15 * 1.2 * 0.9) + (30 * 2 * 0.9) = 70.2 usd
     *
     * 2. lp price drops to 0.5 usdc/lp -> position become repurchaseable
     *      - alice total borrowing power = (15 * 1.2 * 0.9) + (30 * 0.5 * 0.9) = 29.7 usd
     *
     * 3. bob repurchase ibWeth collateral with 5 usdc, bob will receive 4.20833.. weth
     *      - 5 / 1.2 = 4.166.. weth will be repurchased by bob
     *      - 4.166.. * 1% = 0.04166.. weth as repurchase reward for bob
     *
     * 4. alice position after repurchase
     *      - alice subaccount 0: weth collateral = 10 - 4.20833.. = 10.79166.. weth
     *      - alice subaccount 0: usdc debt = 30 - 5 = 25 usdc
     */
    address _collatToken = address(ibWeth);
    address _debtToken = address(usdc);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _amountToRepurchase = 5 ether;

    vm.prank(ALICE);
    IMoneyMarket(moneyMarketDiamond).deposit(address(weth), 40 ether);

    // increase ibWeth price to 1.2 weth/ibWeth
    vm.prank(BOB);
    weth.transfer(moneyMarketDiamond, 28 ether);

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 40 ether);
    farmFacet.addFarmPosition(subAccount0, _lpToken, 30 ether, 30 ether, 0);
    vm.stopPrank();

    uint256 _bobIbWethBalanceBefore = ibWeth.balanceOf(BOB);
    uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);

    mockOracle.setTokenPrice(address(_lpToken), 0.5 ether);

    vm.prank(BOB);
    liquidationFacet.repurchase(ALICE, subAccount0, _debtToken, _collatToken, _lpToken, _amountToRepurchase, 0);

    // check bob balance
    uint256 _ibWethReceivedFromRepurchase = _calcCollatRepurchaserShouldReceive(_amountToRepurchase, 1.2 ether);
    assertEq(ibWeth.balanceOf(BOB) - _bobIbWethBalanceBefore, _ibWethReceivedFromRepurchase, "bob ibWeth diff");
    assertEq(_bobUsdcBalanceBefore - usdc.balanceOf(BOB), _amountToRepurchase, "bob usdc diff");

    // check alice position
    assertEq(
      collateralFacet.subAccountCollatAmount(_aliceSubAccount0, _collatToken),
      15 ether - _ibWethReceivedFromRepurchase, // TODO: account for repurchase fee
      "alice remaining ibWeth collat"
    );
    (, uint256 _aliceUsdcDebtValue) = farmFacet.getDebt(ALICE, subAccount0, address(usdc), _lpToken);
    assertEq(_aliceUsdcDebtValue, 25 ether, "alice remaining usdc debt");
  }

  function testRevert_WhenRepurchaseHealthySubAccount() external {
    address _collatToken = address(weth);
    address _debtToken = address(usdc);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _amountToRepurchase = 5 ether;

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 40 ether);
    farmFacet.addFarmPosition(subAccount0, _lpToken, 30 ether, 30 ether, 0);
    vm.stopPrank();

    vm.prank(BOB);
    vm.expectRevert(abi.encodeWithSelector(ILYFLiquidationFacet.LYFLiquidationFacet_Healthy.selector));
    liquidationFacet.repurchase(ALICE, subAccount0, _debtToken, _collatToken, _lpToken, _amountToRepurchase, 0);
  }

  function testRevert_WhenRepurchaseMoreThanHalfOfDebt_WhileThereIs2DebtPosition() external {
    address _collatToken = address(btc);
    address _debtToken = address(usdc);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _amountToRepurchase = 40 ether;

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 4 ether);
    // open farm with 29 weth, 31 usdc borrowed
    farmFacet.addFarmPosition(subAccount0, _lpToken, 29 ether, 31 ether, 0);
    vm.stopPrank();

    mockOracle.setTokenPrice(address(_lpToken), 0.5 ether);

    // bob try to liquidate 40 usdc, get capped at 31 usdc, should fail because it is more than half of total debt
    vm.prank(BOB);
    vm.expectRevert(abi.encodeWithSelector(ILYFLiquidationFacet.LYFLiquidationFacet_RepayDebtValueTooHigh.selector));
    liquidationFacet.repurchase(ALICE, subAccount0, _debtToken, _collatToken, _lpToken, _amountToRepurchase, 0);
  }

  function testRevert_WhenNotEnoughCollatToPayForDebtAmount() external {
    address _collatToken = address(btc);
    address _debtToken = address(usdc);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _amountToRepurchase = 30 ether;

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 4 ether);
    // open farm with 29 weth, 31 usdc borrowed
    farmFacet.addFarmPosition(subAccount0, _lpToken, 30 ether, 30 ether, 0);
    vm.stopPrank();

    mockOracle.setTokenPrice(address(_lpToken), 0.5 ether);
    mockOracle.setTokenPrice(address(btc), 0.5 ether);

    // bob try to liquidate 30 usdc, should fail because btc collat value is less than 30 usd
    vm.prank(BOB);
    vm.expectRevert(abi.encodeWithSelector(ILYFLiquidationFacet.LYFLiquidationFacet_InsufficientAmount.selector));
    liquidationFacet.repurchase(ALICE, subAccount0, _debtToken, _collatToken, _lpToken, _amountToRepurchase, 0);
  }

  function testRevert_WhenCollatOutIsLessThanExpected() external {
    address _collatToken = address(weth);
    address _debtToken = address(usdc);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _amountToRepurchase = 5 ether;

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 40 ether);
    farmFacet.addFarmPosition(subAccount0, _lpToken, 30 ether, 30 ether, 0);
    vm.stopPrank();

    mockOracle.setTokenPrice(address(_lpToken), 0.5 ether);

    vm.prank(BOB);
    vm.expectRevert(abi.encodeWithSelector(ILYFLiquidationFacet.LYFLiquidationFacet_TooLittleReceived.selector));
    liquidationFacet.repurchase(
      ALICE,
      subAccount0,
      _debtToken,
      _collatToken,
      _lpToken,
      _amountToRepurchase,
      5.06 ether
    );
  }

  function testRevert_WhenUnauthorizedUserCallLiquidate_ShouldRevert() external {
    vm.expectRevert(abi.encodeWithSelector(ILYFLiquidationFacet.LYFLiquidationFacet_Unauthorized.selector));
    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      subAccount0,
      address(0),
      address(0),
      address(0),
      0,
      abi.encode()
    );
  }

  function testRevert_WhenCallLiquidateWithAuthorizedStrat_ShouldRevert() external {
    vm.expectRevert(abi.encodeWithSelector(ILYFLiquidationFacet.LYFLiquidationFacet_Unauthorized.selector));
    vm.prank(liquidator);
    liquidationFacet.liquidationCall(
      address(0),
      ALICE,
      subAccount0,
      address(0),
      address(0),
      address(0),
      0,
      abi.encode()
    );
  }

  function testCorrectness_WhenSubAccountWentUnderWater_ShouldBeAbleToLiquidate() external {
    /**
     * scenario:
     *
     * 1. @ 1 usdc/weth: alice add collateral 40 weth, open farm with 30 weth, 30 usdc
     *      - 30 weth collateral is used to open position -> 10 weth left as collateral
     *      - alice need to borrow 30 usdc
     *      - alice total borrowing power = (10 * 1 * 0.9) + (30 * 2 * 0.9) = 63 usd
     *      - alice used borrowing power = (30 * 1)/0.9 = 33.333333333333333333 usd
     *
     * 2. lp price drops to 0.5 usdc/lp -> position become repurchaseable
     *      - alice total borrowing power = (10 * 1 * 0.9) + (30 * 0.5 * 0.9) = 22.5 usd
     *
     * 3. liquidator liquidate alice position
     *      - repay 10 USDC
     *      - treasury get 1% of repaid debt = 10 * 1/100 = 0.1
     *      - actual repay = 10 - 0.1 = 9.9 USDC
     *
     * 4. alice position after liquidate
     *      - alice subaccount 0: weth collateral = 10 - 10 = 0 weth
     *      - alice subaccount 0: usdc debt = 30 - 9.9 = 20.1 usdc
     */

    address _collatToken = address(weth);
    address _debtToken = address(usdc);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _repayAmount = 10 ether;

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 40 ether);
    farmFacet.addFarmPosition(subAccount0, _lpToken, 30 ether, 30 ether, 0);
    vm.stopPrank();

    assertEq(collateralFacet.subAccountCollatAmount(_aliceSubAccount0, address(weth)), 10 ether);
    assertEq(farmFacet.getTotalBorrowingPower(ALICE, subAccount0), 63 ether);
    assertEq(farmFacet.getTotalUsedBorrowedPower(ALICE, subAccount0), 33.333333333333333333 ether);

    usdc.mint(liquidator, 10000 ether);

    uint256 _treasuryUsdcBalanceBefore = usdc.balanceOf(treasury);

    mockOracle.setTokenPrice(address(_lpToken), 0.5 ether);
    vm.startPrank(liquidator);

    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      subAccount0,
      _debtToken,
      _collatToken,
      _lpToken,
      _repayAmount,
      abi.encode()
    );
    vm.stopPrank();

    // collateral is sold to repay
    assertEq(collateralFacet.subAccountCollatAmount(_aliceSubAccount0, address(weth)), 0);

    // debt reduce
    (, uint256 _aliceUsdcDebtValue) = farmFacet.getDebt(ALICE, subAccount0, address(usdc), _lpToken);
    assertEq(_aliceUsdcDebtValue, 20.1 ether);

    // treasury get fee
    assertEq(usdc.balanceOf(treasury) - _treasuryUsdcBalanceBefore, 0.1 ether);
  }
}
