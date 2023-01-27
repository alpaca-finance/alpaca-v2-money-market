// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, console } from "./LYF_BaseTest.t.sol";

// libraries
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";

// interfaces
import { ILYFLiquidationFacet } from "../../contracts/lyf/interfaces/ILYFLiquidationFacet.sol";
import { IMoneyMarket } from "../../contracts/lyf/interfaces/IMoneyMarket.sol";

// contract
import { PancakeswapV2IbTokenLiquidationStrategy } from "../../contracts/money-market/PancakeswapV2IbTokenLiquidationStrategy.sol";

// mocks
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockLiquidationStrategy } from "../mocks/MockLiquidationStrategy.sol";
import { MockRouter02 } from "../mocks/MockRouter02.sol";

contract LYF_Liquidation_IbLiquidationCallTest is LYF_BaseTest {
  PancakeswapV2IbTokenLiquidationStrategy _ibTokenLiquidationStrat;
  MockRouter02 internal router;

  function setUp() public override {
    super.setUp();

    router = new MockRouter02(address(wethUsdcLPToken), address(mockOracle));
    usdc.mint(address(router), 100 ether); // prepare for swap

    _ibTokenLiquidationStrat = new PancakeswapV2IbTokenLiquidationStrategy(
      address(router),
      address(moneyMarketDiamond)
    );

    // whitelist
    address[] memory _liquidationStrats = new address[](1);
    _liquidationStrats[0] = address(_ibTokenLiquidationStrat);
    adminFacet.setLiquidationStratsOk(_liquidationStrats, true);

    address[] memory _liquidators = new address[](1);
    _liquidators[0] = address(liquidator);
    adminFacet.setLiquidatorsOk(_liquidators, true);

    address[] memory _liquidationExecutors = new address[](1);
    _liquidationExecutors[0] = address(lyfDiamond);
    _ibTokenLiquidationStrat.setCallersOk(_liquidationExecutors, true);

    address[] memory _paths = new address[](2);
    _paths[0] = address(btc);
    _paths[1] = address(usdc);

    PancakeswapV2IbTokenLiquidationStrategy.SetPathParams[]
      memory _setPathsInputs = new PancakeswapV2IbTokenLiquidationStrategy.SetPathParams[](1);
    _setPathsInputs[0] = PancakeswapV2IbTokenLiquidationStrategy.SetPathParams({ path: _paths });

    _ibTokenLiquidationStrat.setPaths(_setPathsInputs);
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
     * 2. lp price drops to 0.5 usdc/lp -> position become liquidatable
     *      - alice total borrowing power = (4 * 10 * 0.9) + (30 * 0.5 * 0.9) = 49.5 usd
     *
     * 3. liquidator liquidate alice position
     *      - repay 5 USDC
     *      - treasury get 1% of repaid debt = 5 * 1/100 = 0.05
     *      - actual repay = 5 + 0.05 = 5.05
     *      - BTC price = 10, need to swap 5.05/10 = 0.505 BTC for 5.05 USDC
     *      - ibBtc/Btc Price = 1, need to withdraw  0.505 ibBTC from MM
     *      - actual repay = 5 USDC
     *
     * 4. alice position after liquidate
     *      - alice subaccount 0: ibBtc collateral = 4 - 0.505 = 3.495 ibBtc
     *      - alice subaccount 0: usdc debt = 30 - 5 = 25 usdc
     *      - lyf USDC outstanding should increase by repaid amount = 5 USDC
     */

    address _collatToken = address(ibBtc);
    address _debtToken = address(usdc);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _repayAmount = 5 ether;

    vm.startPrank(ALICE);
    btc.approve(moneyMarketDiamond, type(uint256).max);
    IMoneyMarket(moneyMarketDiamond).deposit(address(btc), 4 ether);

    ibBtc.approve(lyfDiamond, type(uint256).max);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 4 ether);
    farmFacet.addFarmPosition(subAccount0, _lpToken, 30 ether, 30 ether, 0);
    vm.stopPrank();

    assertEq(viewFacet.getSubAccountTokenCollatAmount(ALICE, subAccount0, _collatToken), 4 ether);
    assertEq(viewFacet.getTotalBorrowingPower(ALICE, subAccount0), 90 ether);
    assertEq(viewFacet.getTotalUsedBorrowingPower(ALICE, subAccount0), 66.666666666666666666 ether);

    usdc.mint(liquidator, 10000 ether);

    uint256 _treasuryUsdcBalanceBefore = usdc.balanceOf(treasury);
    uint256 _liquidatorUsdcBalanceBefore = usdc.balanceOf(liquidator);
    uint256 _usdcOutStandingBefore = viewFacet.getOutstandingBalanceOf(address(usdc));

    mockOracle.setLpTokenPrice(address(_lpToken), 0.5 ether);
    console.log("[T]Before liquidationCall");
    vm.startPrank(liquidator);
    liquidationFacet.liquidationCall(
      address(_ibTokenLiquidationStrat),
      ALICE,
      subAccount0,
      _debtToken,
      _collatToken,
      _lpToken,
      _repayAmount,
      0
    );
    console.log("[T]After liquidationCall");
    vm.stopPrank();

    // ibBtc collateral is sold to repay
    assertEq(viewFacet.getSubAccountTokenCollatAmount(ALICE, subAccount0, address(ibBtc)), 3.495 ether);

    // debt reduce
    (, uint256 _aliceUsdcDebtValue) = viewFacet.getSubAccountDebt(ALICE, subAccount0, address(usdc), _lpToken);
    assertEq(_aliceUsdcDebtValue, 25.0 ether);

    // LYF outstanding
    assertEq(viewFacet.getOutstandingBalanceOf(address(usdc)) - _usdcOutStandingBefore, _repayAmount);

    // liquidator get fee
    assertEq(usdc.balanceOf(liquidator) - _liquidatorUsdcBalanceBefore, 0.025 ether);
    // treasury get fee
    assertEq(usdc.balanceOf(treasury) - _treasuryUsdcBalanceBefore, 0.025 ether);
  }
}
