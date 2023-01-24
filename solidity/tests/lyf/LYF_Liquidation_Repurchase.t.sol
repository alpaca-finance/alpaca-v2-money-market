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

    usdc.mint(address(mockLiquidationStrategy), 1000 ether);

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
    farmFacet.addFarmPosition(subAccount0, _lpToken, 30 ether, 30 ether, 0);
    vm.stopPrank();

    uint256 _bobWethBalanceBefore = weth.balanceOf(BOB);
    uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);

    /*
     * 2. lp price drops to 0.5 usdc/lp -> position become repurchaseable
     *      - alice total borrowing power = (10 * 1 * 0.9) + (30 * 0.5 * 0.9) = 22.5 usd
     */
    mockOracle.setLpTokenPrice(address(_lpToken), 0.5 ether);

    uint256 _amountToRepurchase = 5 ether;
    uint256 _fee = 0.05 ether; // (1%)
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
    assertEq(_aliceUsdcDebtValue, 25 ether, "alice debt remaining");

    // treasury reward check
    assertEq(usdc.balanceOf(treasury), _fee, "treasury received repaid fee");
  }
}
