// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, console } from "./LYF_BaseTest.t.sol";

// interfaces
import { ILYFLiquidationFacet } from "../../contracts/lyf/interfaces/ILYFLiquidationFacet.sol";
import { IMoneyMarket } from "../../contracts/lyf/interfaces/IMoneyMarket.sol";

// mocks
import { MockERC20 } from "../mocks/MockERC20.sol";

// libraries
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";

contract LYF_LiquidationFacetTest is LYF_BaseTest {
  uint256 _subAccountId = 0;
  address _aliceSubAccount0 = LibLYF01.getSubAccount(ALICE, _subAccountId);

  uint256 constant REPURCHASE_REWARD_BPS = 100;
  uint256 constant REPURCHASE_FEE_BPS = 100;

  function setUp() public override {
    super.setUp();
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

  // LP liquidation test

  function testCorrectness_WhenPartialLiquidateLP_ShouldWork() external {
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
     * 3. we try to liquidate 5 lp to repay 4 usdc and 4 weth
     *      - 5 weth can be redeemed but no weth debt, so 5 weth is added as collateral
     *      - 5 usdc can be redeemed so 4 usdc is repaid, 1 usdc is added as collateral
     *
     * 4. alice position after repurchase
     *      - alice subaccount 0: lp collateral = 30 - 5 = 25 lp
     *      - alice subaccount 0: weth collateral = 10 + 5 = 15 weth
     *      - alice subaccount 0: usdc collateral = 0 + 1 = 1 usdc
     *      - alice subaccount 0: weth debt = 0
     *      - alice subaccount 0: usdc debt = 30 - 4 = 26 usdc
     */
    address _collatToken = address(weth);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _lpAmountToLiquidate = 5 ether;

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 40 ether);
    farmFacet.addFarmPosition(subAccount0, _lpToken, 30 ether, 30 ether, 0);
    vm.stopPrank();

    mockOracle.setTokenPrice(address(_lpToken), 0.5 ether);
    mockRouter.setRemoveLiquidityAmountsOut(5 ether, 5 ether);

    liquidationFacet.liquidateLP(ALICE, subAccount0, _lpToken, _lpAmountToLiquidate, 4 ether, 4 ether);

    // check alice position
    assertEq(
      collateralFacet.subAccountCollatAmount(_aliceSubAccount0, _lpToken),
      25 ether,
      "alice remaining lp collat"
    );
    assertEq(
      collateralFacet.subAccountCollatAmount(_aliceSubAccount0, address(weth)),
      15 ether,
      "alice remaining weth collat"
    );
    assertEq(
      collateralFacet.subAccountCollatAmount(_aliceSubAccount0, address(usdc)),
      1 ether,
      "alice remaining usdc collat"
    );
    (, uint256 _aliceWethDebtValue) = farmFacet.getDebt(ALICE, subAccount0, address(weth), _lpToken);
    assertEq(_aliceWethDebtValue, 0, "alice remaining weth debt");
    (, uint256 _aliceUsdcDebtValue) = farmFacet.getDebt(ALICE, subAccount0, address(usdc), _lpToken);
    assertEq(_aliceUsdcDebtValue, 26 ether, "alice remaining usdc debt");
  }

  function testCorrectness_WhenLiquidateLPMoreThanCollateral_ShouldLiquidateAllLP() external {
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
     * 3. we try to liquidate 40 lp (capped to 30) to repay 5 usdc and 5 weth
     *      - 30 weth can be redeemed but no weth debt, so 30 weth is added as collateral
     *      - 30 usdc can be redeemed so 5 usdc is repaid, 25 usdc is added as collateral
     *
     * 4. alice position after repurchase
     *      - alice subaccount 0: lp collateral = 30 - 30 = 0 lp
     *      - alice subaccount 0: weth collateral = 10 + 30 = 40 weth
     *      - alice subaccount 0: usdc collateral = 0 + 25 = 25 usdc
     *      - alice subaccount 0: weth debt = 0
     *      - alice subaccount 0: usdc debt = 30 - 5 = 25 usdc
     */
    address _collatToken = address(weth);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _lpAmountToLiquidate = 40 ether;

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 40 ether);
    farmFacet.addFarmPosition(subAccount0, _lpToken, 30 ether, 30 ether, 0);
    vm.stopPrank();

    mockOracle.setTokenPrice(address(_lpToken), 0.5 ether);
    mockRouter.setRemoveLiquidityAmountsOut(30 ether, 30 ether);

    liquidationFacet.liquidateLP(ALICE, subAccount0, _lpToken, _lpAmountToLiquidate, 5 ether, 5 ether);

    // check alice position
    assertEq(collateralFacet.subAccountCollatAmount(_aliceSubAccount0, _lpToken), 0, "alice remaining lp collat");
    assertEq(
      collateralFacet.subAccountCollatAmount(_aliceSubAccount0, address(weth)),
      40 ether,
      "alice remaining weth collat"
    );
    assertEq(
      collateralFacet.subAccountCollatAmount(_aliceSubAccount0, address(usdc)),
      25 ether,
      "alice remaining usdc collat"
    );
    (, uint256 _aliceWethDebtValue) = farmFacet.getDebt(ALICE, subAccount0, address(weth), _lpToken);
    assertEq(_aliceWethDebtValue, 0, "alice remaining weth debt");
    (, uint256 _aliceUsdcDebtValue) = farmFacet.getDebt(ALICE, subAccount0, address(usdc), _lpToken);
    assertEq(_aliceUsdcDebtValue, 25 ether, "alice remaining usdc debt");
  }

  function testCorrectness_WhenPartialLiquidateLPThatAlsoUsedAsCollat_ShouldWork() external {
    /**
     * scenario:
     *
     * 1. @ 2 usd/lp, alice add collateral 20 lp, open farm with 30 weth, 30 usdc
     *      - alice need to borrow 30 weth, 30 usdc
     *      - alice total borrowing power = (20 * 2 * 0.9) + (30 * 2 * 0.9) = 90 usd
     *
     * 2. lp price drops to 0.5 usd/lp -> position become liquidatable
     *      - alice total borrowing power = (20 * 0.5 * 0.9) + (30 * 0.5 * 0.9) = 22.5 usd
     *
     * 3. we try to liquidate 5 lp collateral and repay debt of 4 usdc, 4 weth
     *      - 5 weth can be redeemed so 4 weth is repaid, 1 weth is add as collateral
     *      - 5 usdc can be redeemed so 4 usdc is repaid, 1 usdc is add as collateral
     *
     * 4. alice position after repurchase
     *      - alice subaccount 0: lp collateral = 50 - 5 = 45 lp
     *      - alice subaccount 0: weth collateral = 1 weth
     *      - alice subaccount 0: usdc collateral = 1 usdc
     *      - alice subaccount 0: weth debt = 30 - 4 = 26 weth
     *      - alice subaccount 0: usdc debt = 30 - 4 = 26 usdc
     */
    address _lpToken = address(wethUsdcLPToken);
    uint256 _lpAmountToLiquidate = 5 ether;

    wethUsdcLPToken.mint(ALICE, 20 ether);
    vm.startPrank(ALICE);
    wethUsdcLPToken.approve(lyfDiamond, type(uint256).max);
    collateralFacet.addCollateral(ALICE, subAccount0, _lpToken, 20 ether);
    farmFacet.addFarmPosition(subAccount0, _lpToken, 30 ether, 30 ether, 0);
    vm.stopPrank();

    mockOracle.setTokenPrice(address(_lpToken), 0.5 ether);
    mockRouter.setRemoveLiquidityAmountsOut(5 ether, 5 ether);

    liquidationFacet.liquidateLP(ALICE, subAccount0, _lpToken, _lpAmountToLiquidate, 4 ether, 4 ether);

    // check alice position
    assertEq(
      collateralFacet.subAccountCollatAmount(_aliceSubAccount0, _lpToken),
      45 ether,
      "alice remaining lp collat"
    );
    assertEq(
      collateralFacet.subAccountCollatAmount(_aliceSubAccount0, address(weth)),
      1 ether,
      "alice remaining weth collat"
    );
    assertEq(
      collateralFacet.subAccountCollatAmount(_aliceSubAccount0, address(usdc)),
      1 ether,
      "alice remaining usdc collat"
    );
    (, uint256 _aliceWethDebtValue) = farmFacet.getDebt(ALICE, subAccount0, address(weth), _lpToken);
    assertEq(_aliceWethDebtValue, 26 ether, "alice remaining weth debt");
    (, uint256 _aliceUsdcDebtValue) = farmFacet.getDebt(ALICE, subAccount0, address(usdc), _lpToken);
    assertEq(_aliceUsdcDebtValue, 26 ether, "alice remaining usdc debt");
  }

  function testCorrectness_WhenLiquidateLPButReceiveTokensLessThanRepayAmount_ShouldWork() external {
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
     * 3. we try to liquidate 5 lp to repay 4 usdc and 4 weth
     *      - 2 weth can be redeemed but no weth debt, so 2 weth is added as collateral
     *      - 2 usdc can be redeemed so 2 usdc is repaid
     *
     * 4. alice position after repurchase
     *      - alice subaccount 0: lp collateral = 30 - 5 = 25 lp
     *      - alice subaccount 0: weth collateral = 10 + 2 = 12 weth
     *      - alice subaccount 0: usdc collateral = 0
     *      - alice subaccount 0: weth debt = 0
     *      - alice subaccount 0: usdc debt = 30 - 2 = 28 usdc
     */
    address _collatToken = address(weth);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _lpAmountToLiquidate = 5 ether;

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 40 ether);
    farmFacet.addFarmPosition(subAccount0, _lpToken, 30 ether, 30 ether, 0);
    vm.stopPrank();

    mockOracle.setTokenPrice(address(_lpToken), 0.5 ether);
    mockRouter.setRemoveLiquidityAmountsOut(2 ether, 2 ether);

    liquidationFacet.liquidateLP(ALICE, subAccount0, _lpToken, _lpAmountToLiquidate, 4 ether, 4 ether);

    // check alice position
    assertEq(
      collateralFacet.subAccountCollatAmount(_aliceSubAccount0, _lpToken),
      25 ether,
      "alice remaining lp collat"
    );
    assertEq(
      collateralFacet.subAccountCollatAmount(_aliceSubAccount0, address(weth)),
      12 ether,
      "alice remaining weth collat"
    );
    assertEq(
      collateralFacet.subAccountCollatAmount(_aliceSubAccount0, address(usdc)),
      0,
      "alice remaining usdc collat"
    );
    (, uint256 _aliceWethDebtValue) = farmFacet.getDebt(ALICE, subAccount0, address(weth), _lpToken);
    assertEq(_aliceWethDebtValue, 0, "alice remaining weth debt");
    (, uint256 _aliceUsdcDebtValue) = farmFacet.getDebt(ALICE, subAccount0, address(usdc), _lpToken);
    assertEq(_aliceUsdcDebtValue, 28 ether, "alice remaining usdc debt");
  }

  // TODO: case LP collat and farm same LP still fail because we didn't deposit LP into masterchef when add collat
  // function testCorrectness_WhenLiquidateLPMoreThanCollateral_AndThatLPAlsoUsedAsCollat_ShouldLiquidateAllLPCollateral() external {
  //   /**
  //    * scenario:
  //    *
  //    * 1. @ 2 usd/lp, alice add collateral 20 lp, open farm with 30 weth, 30 usdc
  //    *      - alice need to borrow 30 weth, 30 usdc
  //    *      - alice total borrowing power = (20 * 2 * 0.9) + (30 * 2 * 0.9) = 90 usd
  //    *
  //    * 2. lp price drops to 0.5 usd/lp -> position become liquidatable
  //    *      - alice total borrowing power = (20 * 0.5 * 0.9) + (30 * 0.5 * 0.9) = 22.5 usd
  //    *
  //    * 3. we try to liquidate 60 lp collateral (cap to 50) and repay debt of 30 usdc, 30 weth
  //    *      - 60 weth can be redeemed so 30 weth is repaid, 30 weth is add as collateral
  //    *      - 60 usdc can be redeemed so 30 usdc is repaid, 30 usdc is add as collateral
  //    *
  //    * 4. alice position after repurchase
  //    *      - alice subaccount 0: lp collateral = 50 - 50 = 0 lp
  //    *      - alice subaccount 0: weth collateral = 30 weth
  //    *      - alice subaccount 0: usdc collateral = 30 usdc
  //    *      - alice subaccount 0: weth debt = 30 - 30 = 0 weth
  //    *      - alice subaccount 0: usdc debt = 30 - 30 = 0 usdc
  //    */
  //   address _lpToken = address(wethUsdcLPToken);
  //   uint256 _lpAmountToLiquidate = 60 ether;

  //   wethUsdcLPToken.mint(ALICE, 20 ether);
  //   vm.startPrank(ALICE);
  //   wethUsdcLPToken.approve(lyfDiamond, type(uint256).max);
  //   collateralFacet.addCollateral(ALICE, subAccount0, _lpToken, 20 ether);
  //   farmFacet.addFarmPosition(subAccount0, _lpToken, 30 ether, 30 ether, 0);
  //   vm.stopPrank();

  //   mockOracle.setTokenPrice(address(_lpToken), 0.5 ether);
  //   mockRouter.setRemoveLiquidityAmountsOut(60 ether, 60 ether);

  //   liquidationFacet.liquidateLP(ALICE, subAccount0, _lpToken, _lpAmountToLiquidate, 4 ether, 4 ether);

  //   // check alice position
  //   assertEq(collateralFacet.subAccountCollatAmount(_aliceSubAccount0, _lpToken), 0, "alice remaining lp collat");
  //   assertEq(
  //     collateralFacet.subAccountCollatAmount(_aliceSubAccount0, address(weth)),
  //     30 ether,
  //     "alice remaining weth collat"
  //   );
  //   assertEq(
  //     collateralFacet.subAccountCollatAmount(_aliceSubAccount0, address(usdc)),
  //     30 ether,
  //     "alice remaining usdc collat"
  //   );
  //   (, uint256 _aliceWethDebtValue) = farmFacet.getDebt(ALICE, subAccount0, address(weth), _lpToken);
  //   assertEq(_aliceWethDebtValue, 0, "alice remaining weth debt");
  //   (, uint256 _aliceUsdcDebtValue) = farmFacet.getDebt(ALICE, subAccount0, address(usdc), _lpToken);
  //   assertEq(_aliceUsdcDebtValue, 0, "alice remaining usdc debt");
  // }

  function testRevert_WhenLiquidateLPOnHealthySubAccount() external {
    address _lpToken = address(wethUsdcLPToken);
    uint256 _lpAmountToLiquidate = 5 ether;

    wethUsdcLPToken.mint(ALICE, 20 ether);
    vm.startPrank(ALICE);
    wethUsdcLPToken.approve(lyfDiamond, type(uint256).max);
    collateralFacet.addCollateral(ALICE, subAccount0, _lpToken, 20 ether);
    farmFacet.addFarmPosition(subAccount0, _lpToken, 30 ether, 30 ether, 0);
    vm.stopPrank();

    vm.expectRevert(abi.encodeWithSelector(ILYFLiquidationFacet.LYFLiquidationFacet_Healthy.selector));
    liquidationFacet.liquidateLP(ALICE, subAccount0, _lpToken, _lpAmountToLiquidate, 4 ether, 4 ether);
  }
}
