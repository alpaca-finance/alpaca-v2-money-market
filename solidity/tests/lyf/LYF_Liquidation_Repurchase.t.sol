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

contract LYF_Liquidation_RepurchaseTest is LYF_BaseTest {
  uint256 _subAccountId = 0;
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
    adminFacet.setLiquidatorsOk(_liquidators, true);

    usdc.mint(address(mockLiquidationStrategy), normalizeEther(1000 ether, usdcDecimal));

    vm.prank(liquidator);
    usdc.approve(lyfDiamond, type(uint256).max);
  }

  function testCorrectness_WhenPartialRepurchase_ShouldWork() external {
    address _collatToken = address(weth);
    address _debtToken = address(usdc);
    address _lpToken = address(wethUsdcLPToken);

    /**
     * scenario:
     *
     * 1. @ 1 usdc/weth: alice add collateral 40 weth, open farm with 30 weth, 30 usdc
     *      - 30 weth collateral is used to open position -> 10 weth left as collateral
     *      - alice need to borrow 30 usdc
     *      - alice total borrowing power = (10 * 1 * 0.9) + (30 * 2 * 0.9) = 63 usd
     */

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 40 ether);
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
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

    uint256 _bobWethBalanceBefore = weth.balanceOf(BOB);
    uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);

    /*
     * 2. lp price drops to 0.5 usdc/lp -> position become repurchaseable
     *      - alice total borrowing power = (10 * 1 * 0.9) + (30 * 0.5 * 0.9) = 22.5 usd
     */
    mockOracle.setLpTokenPrice(address(_lpToken), 0.5 ether);

    uint256 _amountToRepurchase = normalizeEther(5 ether, usdcDecimal);
    uint256 _fee = normalizeEther(0.05 ether, usdcDecimal); // (1%)
    uint256 _amountToRepurchaseWithFee = _amountToRepurchase + _fee;
    /*
     * 3. bob repurchase weth collateral with 5.05 usdc (including fee), bob will receive 5.05 weth
     *      - fee 1%, premium 1%
     *      - repay without fee = 5 (5.05 * 100 / 101)
     *      - reward for bob is 5.05 * 1% = 0.0505
     *      - collat amount out 5.1005 weth
     *
     * 4. alice position after repurchase
     *      - alice subaccount 0: weth collateral = 10 - 5.1005 = 4.8995 weth
     *      - alice subaccount 0: usdc debt = 30 - 5 = 25 usdc
     */
    vm.prank(BOB);
    liquidationFacet.repurchase(ALICE, subAccount0, _debtToken, _collatToken, _lpToken, _amountToRepurchaseWithFee, 0);

    // check bob balance
    assertEq(weth.balanceOf(BOB) - _bobWethBalanceBefore, 5.1005 ether, "bob received collat amount");
    assertEq(_bobUsdcBalanceBefore - usdc.balanceOf(BOB), _amountToRepurchaseWithFee, "bob repaid amount");

    // check alice position
    assertEq(
      viewFacet.getSubAccountTokenCollatAmount(ALICE, _subAccountId, _collatToken),
      4.8995 ether,
      "alice collat remaining"
    );
    (, uint256 _aliceUsdcDebtValue) = viewFacet.getSubAccountDebt(ALICE, subAccount0, address(usdc), _lpToken);
    assertEq(_aliceUsdcDebtValue, normalizeEther(25 ether, usdcDecimal), "alice debt remaining");

    // treasury reward check
    assertEq(usdc.balanceOf(liquidationTreasury), _fee, "treasury received repaid fee");
  }

  function testCorrectness_WhenRepurchaseMoreThanDebt_ShouldRepurchaseAllDebtOnThatToken() external {
    /**
     * scenario:
     *
     * 1. @ 10 usdc/btc, 1 usdc/weth: alice add collateral 4 btc, open farm with 30 weth, 30 usdc
     *      - alice need to borrow 30 usdc, 30 weth -> borrowed value = 60 usd
     *
     */
    address _collatToken = address(btc);
    address _debtToken = address(usdc);
    address _lpToken = address(wethUsdcLPToken);

    vm.startPrank(ALICE);
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

    uint256 _bobBtcBalanceBefore = btc.balanceOf(BOB);
    uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);

    /**
     * 2. lp price drops to 0.5 usdc/lp -> position become repurchaseable
     *      - alice total borrowing power = (10 * 4 * 0.9) + (30 * 0.5 * 0.9) = 49.5 usd
     */
    mockOracle.setLpTokenPrice(address(_lpToken), 0.5 ether);

    /**
     * 3. bob repurchase btc collateral with 40 usdc -> capped at 30.3 usdc, bob will receive 3.03 btc
     *      - fee 1%, premium 1%
     *      - max repay amount is 30.3 ether
     *      - repay without fee = 30 (30.3 * 100 / 101)
     *      - reward for bob is 30.3 * 1% = 0.303
     *      - total collat value = 30.603 * 1 = 30.603 USD
     *      - collat amount out 30.603 / 10 = 3.0603 BTC
     * 4. alice position after repurchase
     *      - alice subaccount 0: btc collateral = 4 - 3.0603 = 0.9397 btc
     *      - alice subaccount 0: usdc debt = 30 - 30 = 0 usdc
     *      - alice subaccount 0: weth debt = 30 weth unchanged
     */

    vm.prank(BOB);
    liquidationFacet.repurchase(
      ALICE,
      subAccount0,
      _debtToken,
      _collatToken,
      _lpToken,
      normalizeEther(50 ether, usdcDecimal),
      0
    );
    // alice debt has only 30 ether
    uint256 _actualRepaidAmount = normalizeEther(30 ether, usdcDecimal);
    uint256 _actualFee = normalizeEther(0.3 ether, usdcDecimal);

    // check bob balance
    assertEq(btc.balanceOf(BOB) - _bobBtcBalanceBefore, 3.0603 ether, "bob received collat amount");
    assertEq(_bobUsdcBalanceBefore - usdc.balanceOf(BOB), _actualRepaidAmount + _actualFee, "bob repaid amount");

    // check alice position
    assertEq(
      viewFacet.getSubAccountTokenCollatAmount(ALICE, _subAccountId, _collatToken),
      0.9397 ether,
      "alice btc collat remaining"
    );
    (, uint256 _aliceUsdcDebtValue) = viewFacet.getSubAccountDebt(ALICE, subAccount0, address(usdc), _lpToken);
    assertEq(_aliceUsdcDebtValue, 0, "alice debt remaining");
    (, uint256 _aliceWethDebtValue) = viewFacet.getSubAccountDebt(ALICE, subAccount0, address(weth), _lpToken);
    assertEq(_aliceWethDebtValue, 30 ether);

    // treasury reward check
    assertEq(usdc.balanceOf(liquidationTreasury), _actualFee, "treasury received repaid fee");
  }

  function testCorrectness_WhenPartialRepurchaseIb_ShouldWork() external {
    /**
     * scenario:
     *
     * 1. @ 1 usdc/weth, 1.2 weth/ibWeth: alice add collateral 40 ibWeth, open farm with 30 weth, 30 usdc
     *      - 30 / 1.2 = 25 ibWeth collateral is redeemed for 30 weth to open position -> 15 ibWeth left as collateral
     *      - alice need to borrow 30 usdc
     *      - alice total borrowing power = (15 * 1.2 * 0.9) + (30 * 2 * 0.9) = 70.2 usd
     */
    address _ibCollat = address(ibWeth);
    address _debtToken = address(usdc);
    address _lpToken = address(wethUsdcLPToken);

    vm.prank(ALICE);
    IMoneyMarket(moneyMarketDiamond).deposit(address(weth), 40 ether);

    // increase ibWeth price to 1.2 weth/ibWeth
    vm.prank(BOB);
    IMoneyMarket(moneyMarketDiamond).deposit(address(weth), 28 ether);
    vm.prank(moneyMarketDiamond);
    ibWeth.onWithdraw(BOB, BOB, 0, 28 ether);

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _ibCollat, 40 ether);
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

    uint256 _bobIbWethBalanceBefore = ibWeth.balanceOf(BOB);
    uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);

    /**
     * 2. lp price drops to 0.5 usdc/lp -> position become repurchaseable
     *      - alice total borrowing power = (15 * 1.2 * 0.9) + (30 * 0.5 * 0.9) = 29.7 usd
     *
     */
    mockOracle.setLpTokenPrice(address(_lpToken), 0.5 ether);

    uint256 _amountToRepurchase = normalizeEther(5 ether, usdcDecimal);
    uint256 _fee = normalizeEther(0.05 ether, usdcDecimal); // (1%)
    uint256 _amountToRepurchaseWithFee = _amountToRepurchase + _fee;
    /**
     * 3. bob repurchase weth collateral with 5.05 usdc (including fee), bob will receive 5.05 weth
     *      - fee 1%, premium 1%, ibWeth price = 1.2, repay token price
     *      - repay without fee = 5 (5.05 * 100 / 101)
     *      - repay value in usd with premium = 5.05 * (1 + 1%) = 5.05 * 1.01 = 5.1005 USD
     *      - ib collat amount out 5.1005 / 1.2 = 4.250416666666666666
     *
     * 4. alice position after repurchase
     *      - alice subaccount 0: ibWeth collateral = 15 - 4.250416666666666666 = 10.749583333333333334 weth
     *      - alice subaccount 0: usdc debt = 30 - 5 = 25 usdc
     */
    vm.prank(BOB);
    liquidationFacet.repurchase(ALICE, subAccount0, _debtToken, _ibCollat, _lpToken, _amountToRepurchaseWithFee, 0);

    // check bob balance
    assertEq(ibWeth.balanceOf(BOB) - _bobIbWethBalanceBefore, 4.250416666666666666 ether, "bob received collat amount");
    assertEq(_bobUsdcBalanceBefore - usdc.balanceOf(BOB), _amountToRepurchaseWithFee, "bob repaid amount");

    // check alice position
    assertEq(
      viewFacet.getSubAccountTokenCollatAmount(ALICE, _subAccountId, _ibCollat),
      10.749583333333333334 ether,
      "alice ib collat remaining"
    );
    (, uint256 _aliceUsdcDebtValue) = viewFacet.getSubAccountDebt(ALICE, subAccount0, address(usdc), _lpToken);
    assertEq(_aliceUsdcDebtValue, normalizeEther(25 ether, usdcDecimal), "alice debt remaining");

    // treasury reward check
    assertEq(usdc.balanceOf(liquidationTreasury), _fee, "treasury received repaid fee");
  }

  function testRevert_WhenRepurchaseHealthySubAccount() external {
    address _collatToken = address(weth);
    address _debtToken = address(usdc);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _amountToRepurchase = normalizeEther(5 ether, usdcDecimal);

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 40 ether);
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

    vm.prank(BOB);
    vm.expectRevert(abi.encodeWithSelector(ILYFLiquidationFacet.LYFLiquidationFacet_Healthy.selector));
    liquidationFacet.repurchase(ALICE, subAccount0, _debtToken, _collatToken, _lpToken, _amountToRepurchase, 0);
  }

  function testRevert_WhenRepurchaseMoreThanHalfOfDebt_WhileThereIs2DebtPosition() external {
    address _collatToken = address(btc);
    address _debtToken = address(usdc);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _amountToRepurchase = normalizeEther(40 ether, usdcDecimal);

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 4 ether);
    // open farm with 29 weth, 31 usdc borrowed
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: _lpToken,
      minLpReceive: 0,
      desiredToken0Amount: 29 ether,
      desiredToken1Amount: normalizeEther(31 ether, usdcDecimal),
      token0ToBorrow: 29 ether,
      token1ToBorrow: normalizeEther(31 ether, usdcDecimal),
      token0AmountIn: 0,
      token1AmountIn: 0
    });
    farmFacet.addFarmPosition(_input);
    vm.stopPrank();

    mockOracle.setLpTokenPrice(address(_lpToken), 0.5 ether);

    // bob try to liquidate 40 usdc, get capped at 31 usdc, should fail because it is more than half of total debt
    vm.prank(BOB);
    vm.expectRevert(abi.encodeWithSelector(ILYFLiquidationFacet.LYFLiquidationFacet_RepayDebtValueTooHigh.selector));
    liquidationFacet.repurchase(ALICE, subAccount0, _debtToken, _collatToken, _lpToken, _amountToRepurchase, 0);
  }

  function testRevert_WhenNotEnoughCollatToPayForDebtAmount() external {
    address _collatToken = address(btc);
    address _debtToken = address(usdc);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _amountToRepurchase = normalizeEther(20.2 ether, usdcDecimal);

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 4 ether);
    // open farm with 29 weth, 31 usdc borrowed
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

    mockOracle.setLpTokenPrice(address(_lpToken), 0.5 ether);
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
    uint256 _amountToRepurchase = normalizeEther(5 ether, usdcDecimal);

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 40 ether);
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

    mockOracle.setLpTokenPrice(address(_lpToken), 0.5 ether);

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
}
