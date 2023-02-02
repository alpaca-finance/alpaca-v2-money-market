// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, console } from "./LYF_BaseTest.t.sol";

// interfaces
import { ILYFLiquidationFacet } from "../../contracts/lyf/interfaces/ILYFLiquidationFacet.sol";
import { IMoneyMarket } from "../../contracts/lyf/interfaces/IMoneyMarket.sol";
import { ILYFFarmFacet } from "../../contracts/lyf/interfaces/ILYFFarmFacet.sol";

// mocks
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockLiquidationStrategy } from "../mocks/MockLiquidationStrategy.sol";

// libraries
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";

contract LYF_Liquidation_LiquidationCallTest is LYF_BaseTest {
  MockLiquidationStrategy internal mockLiquidationStrategy;

  struct CacheState {
    // general
    uint256 lyfDebtTokenOutStanding;
    // debt
    uint256 debtPoolTotalValue;
    uint256 debtPoolShare;
    uint256 subAccountDebtValue;
    // collat
    uint256 tokenCollatAmount;
    uint256 subAccountCollatAmount;
    // fee
    uint256 treasuryDebtTokenBalance;
    uint256 liquidatorDebtTokenBalance;
  }

  function _getCacheState(
    address _account,
    uint256 _subAccountId,
    address _collatToken,
    address _debtToken,
    address _lpToken
  ) internal view returns (CacheState memory _cachestate) {
    uint256 _debtPoolId = viewFacet.getDebtPoolIdOf(_debtToken, _lpToken);
    uint256 _userDebtTokenValue;
    (, _userDebtTokenValue) = viewFacet.getSubAccountDebt(_account, _subAccountId, address(usdc), _lpToken);

    _cachestate = CacheState({
      lyfDebtTokenOutStanding: viewFacet.getOutstandingBalanceOf(_debtToken),
      debtPoolTotalValue: viewFacet.getDebtPoolTotalValue(_debtPoolId),
      debtPoolShare: viewFacet.getDebtPoolTotalShare(_debtPoolId),
      subAccountDebtValue: _userDebtTokenValue,
      tokenCollatAmount: viewFacet.getTokenCollatAmount(_collatToken),
      subAccountCollatAmount: viewFacet.getSubAccountTokenCollatAmount(ALICE, _subAccountId, _collatToken),
      treasuryDebtTokenBalance: usdc.balanceOf(liquidationTreasury),
      liquidatorDebtTokenBalance: usdc.balanceOf(liquidator)
    });
  }

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

  function testRevert_WhenLiquidateWhileSubAccountIsHealthy() external {
    /**
     * scenario:
     *
     * 1. @ 1 usdc/weth: alice add collateral 40 weth, open farm with 30 weth, 30 usdc
     *      - 30 weth collateral is used to open position -> 10 weth left as collateral
     *      - alice need to borrow 30 usdc
     *      - alice total borrowing power = (10 * 1 * 0.9) + (30 * 2 * 0.9) = 63 usd
     *      - alice used borrowing power = (30 * 1)/0.9 = 33.333333333333333333 usd
     **/
    address _collatToken = address(weth);
    address _debtToken = address(usdc);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _repayAmount = normalizeEther(10 ether, usdcDecimal);

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 40 ether);
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: _lpToken,
      token0: address(weth),
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

    vm.startPrank(liquidator);
    vm.expectRevert(abi.encodeWithSelector(ILYFLiquidationFacet.LYFLiquidationFacet_Healthy.selector));
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
  }

  function testRevert_WhenLiquidateMoreThanThreshold() external {
    address _debtToken = address(usdc);
    address _collatToken = address(weth);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _repayAmount = type(uint256).max;

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 40 ether);
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: _lpToken,
      token0: address(weth),
      minLpReceive: 0,
      desiredToken0Amount: 30 ether,
      desiredToken1Amount: normalizeEther(30 ether, usdcDecimal),
      token0ToBorrow: 20 ether,
      token1ToBorrow: normalizeEther(30 ether, usdcDecimal),
      token0AmountIn: 10 ether,
      token1AmountIn: 0 ether
    });
    farmFacet.addFarmPosition(_input);
    vm.stopPrank();

    mockOracle.setLpTokenPrice(address(_lpToken), 0.5 ether);

    // alice has 40 weth collat, 30 usdc debt, 20 weth debt
    // repay 30 usdc should fail since repay more than 50% of useBorrowingPower
    vm.prank(liquidator);
    vm.expectRevert(
      abi.encodeWithSelector(ILYFLiquidationFacet.LYFLiquidationFacet_RepayAmountExceedThreshold.selector)
    );
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
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: _lpToken,
      token0: address(weth),
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

    assertEq(viewFacet.getSubAccountTokenCollatAmount(ALICE, subAccount0, address(weth)), 10 ether);
    assertEq(viewFacet.getTotalBorrowingPower(ALICE, subAccount0), 63 ether);
    assertEq(viewFacet.getTotalUsedBorrowingPower(ALICE, subAccount0), 33.333333333333333333 ether);

    usdc.mint(liquidator, 10000 ether);

    CacheState memory _stateBefore = _getCacheState(ALICE, subAccount0, _collatToken, _debtToken, _lpToken);

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

    CacheState memory _stateAfter = _getCacheState(ALICE, subAccount0, _collatToken, _debtToken, _lpToken);
    // collateral is sold to repay
    assertEq(_stateAfter.subAccountCollatAmount, 0);

    // debt reduce
    assertEq(_stateBefore.debtPoolTotalValue - _stateAfter.debtPoolTotalValue, 9900991);
    assertEq(_stateAfter.subAccountDebtValue, 20099009);

    // reserve
    assertEq(_stateAfter.lyfDebtTokenOutStanding - _stateBefore.lyfDebtTokenOutStanding, 9900991);

    // liquidator fee
    assertEq(_stateAfter.liquidatorDebtTokenBalance - _stateBefore.liquidatorDebtTokenBalance, 49504);
    // treasury get fee
    assertEq(_stateAfter.treasuryDebtTokenBalance - _stateBefore.treasuryDebtTokenBalance, 49505);
  }
}
