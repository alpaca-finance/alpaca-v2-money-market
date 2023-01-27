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

contract LYF_Liquidation_LiquidationCallTest is LYF_BaseTest {
  uint256 _subAccountId = 0;
  MockLiquidationStrategy internal mockLiquidationStrategy;

  struct CacheState {
    // general
    uint256 lyfReserveToken;
    uint256 ibTokenTotalSupply;
    uint256 treasuryDebtTokenBalance;
    uint256 liquidatorDebtTokenBalance;
    // debt
    uint256 debtPoolTotalValue;
    uint256 debtPoolShare;
    uint256 subAccountDebtShare;
    // collat
    uint256 tokenCollatAmount;
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

    usdc.mint(address(mockLiquidationStrategy), 1000 ether);

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
    uint256 _repayAmount = 10 ether;

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 40 ether);
    farmFacet.addFarmPosition(subAccount0, _lpToken, 30 ether, 30 ether, 0);
    vm.stopPrank();

    assertEq(viewFacet.getSubAccountTokenCollatAmount(ALICE, _subAccountId, address(weth)), 10 ether);
    assertEq(viewFacet.getTotalBorrowingPower(ALICE, subAccount0), 63 ether);
    assertEq(viewFacet.getTotalUsedBorrowingPower(ALICE, subAccount0), 33.333333333333333333 ether);

    usdc.mint(liquidator, 10000 ether);

    uint256 _treasuryUsdcBalanceBefore = usdc.balanceOf(treasury);
    uint256 _liquidatorUsdcBalanceBefore = usdc.balanceOf(liquidator);

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
    assertEq(_aliceUsdcDebtValue, 20099009900990099009);

    // reserve

    // liquidator fee
    assertEq(usdc.balanceOf(liquidator) - _liquidatorUsdcBalanceBefore, 49504950495049504);
    // treasury get fee
    assertEq(usdc.balanceOf(treasury) - _treasuryUsdcBalanceBefore, 49504950495049505);
  }
}
