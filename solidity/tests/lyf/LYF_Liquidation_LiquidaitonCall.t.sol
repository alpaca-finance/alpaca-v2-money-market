// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, console } from "./LYF_BaseTest.t.sol";

// interfaces
import { ILYFLiquidationFacet } from "../../contracts/lyf/interfaces/ILYFLiquidationFacet.sol";
import { ILYFFarmFacet } from "../../contracts/lyf/interfaces/ILYFFarmFacet.sol";
import { IMoneyMarket } from "../../contracts/lyf/interfaces/IMoneyMarket.sol";

// mocks
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockLiquidationStrategy } from "../mocks/MockLiquidationStrategy.sol";

// libraries
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";

contract LYF_Liquidation_LiquidationCallTest is LYF_BaseTest {
  uint256 _subAccountId = 0;
  MockLiquidationStrategy internal mockLiquidationStrategy;
  address constant liquidator = address(1000);

  function setUp() public override {
    super.setUp();

    mockLiquidationStrategy = new MockLiquidationStrategy(address(mockOracle));

    address[] memory _liquidationStrats = new address[](1);
    _liquidationStrats[0] = address(mockLiquidationStrategy);
    adminFacet.setLiquidationStratsOk(_liquidationStrats, true);

    address[] memory _liquidators = new address[](1);
    _liquidators[0] = address(liquidator);
    adminFacet.setLiquidatorsOk(_liquidators, true);

    usdc.mint(address(mockLiquidationStrategy), normalizeEther(1000 ether, usdcDecimal));

    vm.prank(liquidator);
    usdc.approve(lyfDiamond, type(uint256).max);
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
      0
    );
  }

  function testRevert_WhenCallLiquidateWithAuthorizedStrat_ShouldRevert() external {
    vm.expectRevert(abi.encodeWithSelector(ILYFLiquidationFacet.LYFLiquidationFacet_Unauthorized.selector));
    vm.prank(liquidator);
    liquidationFacet.liquidationCall(address(0), ALICE, subAccount0, address(0), address(0), address(0), 0, 0);
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
    uint256 _repayAmount = normalizeEther(10 ether, usdcDecimal);

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 40 ether);
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: _lpToken,
      minLpReceive: 0,
      desiredToken0Amount: 30 ether,
      desiredToken1Amount: normalizeEther(30 ether, usdcDecimal),
      token0ToBorrow: 0,
      token1ToBorrow: normalizeEther(30 ether, usdcDecimal),
      token0AmountIn: 0,
      token1AmountIn: 0
    });
    farmFacet.addFarmPosition(_input);
    vm.stopPrank();

    assertEq(viewFacet.getSubAccountTokenCollatAmount(ALICE, _subAccountId, address(weth)), 10 ether);
    assertEq(viewFacet.getTotalBorrowingPower(ALICE, subAccount0), 63 ether);
    assertEq(viewFacet.getTotalUsedBorrowingPower(ALICE, subAccount0), 33.333333333333333333 ether);

    usdc.mint(liquidator, normalizeEther(10000 ether, usdcDecimal));

    uint256 _treasuryUsdcBalanceBefore = usdc.balanceOf(liquidationTreasury);

    mockOracle.setLpTokenPrice(address(_lpToken), 0.5 ether);
    vm.startPrank(liquidator);

    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      subAccount0,
      _debtToken,
      _collatToken,
      _lpToken,
      _repayAmount,
      0
    );
    vm.stopPrank();

    // collateral is sold to repay
    assertEq(viewFacet.getSubAccountTokenCollatAmount(ALICE, _subAccountId, address(weth)), 0);

    // debt reduce
    (, uint256 _aliceUsdcDebtValue) = viewFacet.getSubAccountDebt(ALICE, subAccount0, address(usdc), _lpToken);
    assertEq(_aliceUsdcDebtValue, normalizeEther(20.1 ether, usdcDecimal));

    // treasury get fee
    assertEq(usdc.balanceOf(liquidationTreasury) - _treasuryUsdcBalanceBefore, normalizeEther(0.1 ether, usdcDecimal));
  }

  function testCorrectness_WhenSubAccountWentUnderWaterWithIbCollat_ShouldBeAbleToLiquidateIbCollat() external {
    /*
     * scenario:
     *
     * 1. @ 1 usdc/weth: alice add collateral 4 ibBtc, open farm with 30 weth, 30 usdc
     *      - alice need to borrow 30 weth and 30 usdc
     *      - alice total borrowing power = (4 * 10 * 0.9) + (30 * 2 * 0.9) = 90 usd
     *      - alice used borrowing power = (30 * 1)/0.9 + (30 * 1)/0.9 = 66.666666666666666666 usd
     *
     * 2. lp price drops to 0.5 usdc/lp -> position become repurchaseable
     *      - alice total borrowing power = (4 * 10 * 0.9) + (30 * 0.5 * 0.9) = 49.5 usd
     *
     * 3. liquidator liquidate alice position
     *      - repay 5 USDC
     *      - treasury get 1% of repaid debt = 5 * 1/100 = 0.05
     *      - actual repay = 5 + 0.05 = 5.05
     *      - BTC price = 10, need to swap 5.05/10 = 0.505 BTC for 5.05 USDC
     *      - actual repay = 5 USDC
     *
     * 4. alice position after liquidate
     *      - alice subaccount 0: ibBtcb collateral = 0
     *      - alice subaccount 0: btc collateral = 4 - 0.505 = 3.495
     *      - alice subaccount 0: usdc debt = 30 - 5 = 25 usdc
     */

    address _collatToken = address(ibBtc);
    address _debtToken = address(usdc);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _repayAmount = normalizeEther(5 ether, usdcDecimal);

    vm.startPrank(ALICE);
    btc.approve(moneyMarketDiamond, type(uint256).max);
    IMoneyMarket(moneyMarketDiamond).deposit(address(btc), 4 ether);

    ibBtc.approve(lyfDiamond, type(uint256).max);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 4 ether);
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: _lpToken,
      minLpReceive: 0,
      desiredToken0Amount: 30 ether,
      desiredToken1Amount: normalizeEther(30 ether, usdcDecimal),
      token0ToBorrow: 30 ether,
      token1ToBorrow: normalizeEther(30 ether, usdcDecimal),
      token0AmountIn: 0,
      token1AmountIn: 0
    });
    farmFacet.addFarmPosition(_input);
    vm.stopPrank();

    assertEq(viewFacet.getSubAccountTokenCollatAmount(ALICE, _subAccountId, _collatToken), 4 ether);
    assertEq(viewFacet.getTotalBorrowingPower(ALICE, subAccount0), 90 ether);
    assertEq(viewFacet.getTotalUsedBorrowingPower(ALICE, subAccount0), 66.666666666666666666 ether);

    usdc.mint(liquidator, normalizeEther(10000 ether, usdcDecimal));

    uint256 _treasuryUsdcBalanceBefore = usdc.balanceOf(liquidationTreasury);

    mockOracle.setLpTokenPrice(address(_lpToken), 0.5 ether);
    vm.startPrank(liquidator);

    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      subAccount0,
      _debtToken,
      _collatToken,
      _lpToken,
      _repayAmount,
      0
    );
    vm.stopPrank();

    // collateral is sold to repay
    assertEq(viewFacet.getSubAccountTokenCollatAmount(ALICE, _subAccountId, address(ibBtc)), 0);
    // leftover underlying token is add to collateral
    assertEq(viewFacet.getSubAccountTokenCollatAmount(ALICE, _subAccountId, address(btc)), 3.495 ether);

    // debt reduce
    (, uint256 _aliceUsdcDebtValue) = viewFacet.getSubAccountDebt(ALICE, subAccount0, address(usdc), _lpToken);
    assertEq(_aliceUsdcDebtValue, normalizeEther(25 ether, usdcDecimal));

    // // treasury get fee
    assertEq(usdc.balanceOf(liquidationTreasury) - _treasuryUsdcBalanceBefore, normalizeEther(0.05 ether, usdcDecimal));
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
     *      - 5 usdc can be redeemed so 3.96 usdc is repaid, 0.04 usdc is taken as fee, 1 usdc is added as collateral
     *
     * 4. alice position after repurchase
     *      - alice subaccount 0: lp collateral = 30 - 5 = 25 lp
     *      - alice subaccount 0: weth collateral = 10 + 5 = 15 weth
     *      - alice subaccount 0: usdc collateral = 0 + 1 = 1 usdc
     *      - alice subaccount 0: weth debt = 0
     *      - alice subaccount 0: usdc debt = 30 - 3.96 = 26.04 usdc
     */
    address _collatToken = address(weth);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _lpAmountToLiquidate = 5 ether;

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 40 ether);
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: _lpToken,
      minLpReceive: 0,
      desiredToken0Amount: 30 ether,
      desiredToken1Amount: normalizeEther(30 ether, usdcDecimal),
      token0ToBorrow: 0,
      token1ToBorrow: normalizeEther(30 ether, usdcDecimal),
      token0AmountIn: 0,
      token1AmountIn: 0
    });
    farmFacet.addFarmPosition(_input);
    vm.stopPrank();

    mockOracle.setLpTokenPrice(address(_lpToken), 0.5 ether);
    mockRouter.setRemoveLiquidityAmountsOut(5 ether, normalizeEther(5 ether, usdcDecimal));

    uint256 _treasuryUsdcBalanceBefore = usdc.balanceOf(liquidationTreasury);

    vm.prank(liquidator);
    liquidationFacet.lpLiquidationCall(
      ALICE,
      subAccount0,
      _lpToken,
      _lpAmountToLiquidate,
      4 ether,
      normalizeEther(4 ether, usdcDecimal)
    );

    // check alice position
    assertEq(
      viewFacet.getSubAccountTokenCollatAmount(ALICE, _subAccountId, _lpToken),
      25 ether,
      "alice remaining lp collat"
    );
    assertEq(
      viewFacet.getSubAccountTokenCollatAmount(ALICE, _subAccountId, address(weth)),
      15 ether,
      "alice remaining weth collat"
    );
    assertEq(
      viewFacet.getSubAccountTokenCollatAmount(ALICE, _subAccountId, address(usdc)),
      normalizeEther(1 ether, usdcDecimal),
      "alice remaining usdc collat"
    );
    (, uint256 _aliceWethDebtValue) = viewFacet.getSubAccountDebt(ALICE, subAccount0, address(weth), _lpToken);
    assertEq(_aliceWethDebtValue, 0, "alice remaining weth debt");
    (, uint256 _aliceUsdcDebtValue) = viewFacet.getSubAccountDebt(ALICE, subAccount0, address(usdc), _lpToken);
    assertEq(_aliceUsdcDebtValue, normalizeEther(26.04 ether, usdcDecimal), "alice remaining usdc debt");

    // check treasury
    assertEq(usdc.balanceOf(liquidationTreasury) - _treasuryUsdcBalanceBefore, normalizeEther(0.04 ether, usdcDecimal));
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
     *      - 30 usdc can be redeemed so 4.95 usdc is repaid, 0.05 usdc is take as fee, 25 usdc is added as collateral
     *
     * 4. alice position after repurchase
     *      - alice subaccount 0: lp collateral = 30 - 30 = 0 lp
     *      - alice subaccount 0: weth collateral = 10 + 30 = 40 weth
     *      - alice subaccount 0: usdc collateral = 0 + 25 = 25 usdc
     *      - alice subaccount 0: weth debt = 0
     *      - alice subaccount 0: usdc debt = 30 - 4.95 = 25.05 usdc
     */
    address _collatToken = address(weth);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _lpAmountToLiquidate = 40 ether;

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 40 ether);
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: _lpToken,
      minLpReceive: 0,
      desiredToken0Amount: 30 ether,
      desiredToken1Amount: normalizeEther(30 ether, usdcDecimal),
      token0ToBorrow: 0,
      token1ToBorrow: normalizeEther(30 ether, usdcDecimal),
      token0AmountIn: 0,
      token1AmountIn: 0
    });
    farmFacet.addFarmPosition(_input);
    vm.stopPrank();

    mockOracle.setLpTokenPrice(address(_lpToken), 0.5 ether);
    mockRouter.setRemoveLiquidityAmountsOut(30 ether, normalizeEther(30 ether, usdcDecimal));

    uint256 _treasuryUsdcBalanceBefore = usdc.balanceOf(liquidationTreasury);

    vm.prank(liquidator);
    liquidationFacet.lpLiquidationCall(
      ALICE,
      subAccount0,
      _lpToken,
      _lpAmountToLiquidate,
      5 ether,
      normalizeEther(5 ether, usdcDecimal)
    );

    // check alice position
    assertEq(viewFacet.getSubAccountTokenCollatAmount(ALICE, _subAccountId, _lpToken), 0, "alice remaining lp collat");
    assertEq(
      viewFacet.getSubAccountTokenCollatAmount(ALICE, _subAccountId, address(weth)),
      40 ether,
      "alice remaining weth collat"
    );
    assertEq(
      viewFacet.getSubAccountTokenCollatAmount(ALICE, _subAccountId, address(usdc)),
      normalizeEther(25 ether, usdcDecimal),
      "alice remaining usdc collat"
    );
    (, uint256 _aliceWethDebtValue) = viewFacet.getSubAccountDebt(ALICE, subAccount0, address(weth), _lpToken);
    assertEq(_aliceWethDebtValue, 0, "alice remaining weth debt");
    (, uint256 _aliceUsdcDebtValue) = viewFacet.getSubAccountDebt(ALICE, subAccount0, address(usdc), _lpToken);
    assertEq(_aliceUsdcDebtValue, normalizeEther(25.05 ether, usdcDecimal), "alice remaining usdc debt");

    // check treasury
    assertEq(usdc.balanceOf(liquidationTreasury) - _treasuryUsdcBalanceBefore, normalizeEther(0.05 ether, usdcDecimal));
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
     *      - 2 usdc can be redeemed so 1.98 usdc is repaid, 0.02 usdc is taken as fee
     *
     * 4. alice position after repurchase
     *      - alice subaccount 0: lp collateral = 30 - 5 = 25 lp
     *      - alice subaccount 0: weth collateral = 10 + 2 = 12 weth
     *      - alice subaccount 0: usdc collateral = 0
     *      - alice subaccount 0: weth debt = 0
     *      - alice subaccount 0: usdc debt = 30 - 1.98 = 28.02 usdc
     */
    address _collatToken = address(weth);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _lpAmountToLiquidate = 5 ether;

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 40 ether);
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: _lpToken,
      minLpReceive: 0,
      desiredToken0Amount: 30 ether,
      desiredToken1Amount: normalizeEther(30 ether, usdcDecimal),
      token0ToBorrow: 0,
      token1ToBorrow: normalizeEther(30 ether, usdcDecimal),
      token0AmountIn: 0,
      token1AmountIn: 0
    });
    farmFacet.addFarmPosition(_input);
    vm.stopPrank();

    mockOracle.setLpTokenPrice(address(_lpToken), 0.5 ether);
    mockRouter.setRemoveLiquidityAmountsOut(2 ether, normalizeEther(2 ether, usdcDecimal));

    uint256 _treasuryUsdcBalanceBefore = usdc.balanceOf(liquidationTreasury);

    vm.prank(liquidator);
    liquidationFacet.lpLiquidationCall(ALICE, subAccount0, _lpToken, _lpAmountToLiquidate, 4 ether, 4 ether);

    // check alice position
    assertEq(
      viewFacet.getSubAccountTokenCollatAmount(ALICE, _subAccountId, _lpToken),
      25 ether,
      "alice remaining lp collat"
    );
    assertEq(
      viewFacet.getSubAccountTokenCollatAmount(ALICE, _subAccountId, address(weth)),
      12 ether,
      "alice remaining weth collat"
    );
    assertEq(
      viewFacet.getSubAccountTokenCollatAmount(ALICE, _subAccountId, address(usdc)),
      0,
      "alice remaining usdc collat"
    );
    (, uint256 _aliceWethDebtValue) = viewFacet.getSubAccountDebt(ALICE, subAccount0, address(weth), _lpToken);
    assertEq(_aliceWethDebtValue, 0, "alice remaining weth debt");
    (, uint256 _aliceUsdcDebtValue) = viewFacet.getSubAccountDebt(ALICE, subAccount0, address(usdc), _lpToken);
    assertEq(_aliceUsdcDebtValue, normalizeEther(28.02 ether, usdcDecimal), "alice remaining usdc debt");

    // check treasury
    assertEq(usdc.balanceOf(liquidationTreasury) - _treasuryUsdcBalanceBefore, normalizeEther(0.02 ether, usdcDecimal));
  }

  function testRevert_WhenLiquidateLPOnHealthySubAccount() external {
    address _lpToken = address(wethUsdcLPToken);
    uint256 _lpAmountToLiquidate = 5 ether;

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 20 ether);
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
      minLpReceive: 0,
      desiredToken0Amount: 30 ether,
      desiredToken1Amount: normalizeEther(30 ether, usdcDecimal),
      token0ToBorrow: 30 ether,
      token1ToBorrow: normalizeEther(30 ether, usdcDecimal),
      token0AmountIn: 0,
      token1AmountIn: 0
    });
    farmFacet.addFarmPosition(_input);
    vm.stopPrank();

    vm.prank(liquidator);
    vm.expectRevert(abi.encodeWithSelector(ILYFLiquidationFacet.LYFLiquidationFacet_Healthy.selector));
    liquidationFacet.lpLiquidationCall(ALICE, subAccount0, _lpToken, _lpAmountToLiquidate, 4 ether, 4 ether);
  }
}
