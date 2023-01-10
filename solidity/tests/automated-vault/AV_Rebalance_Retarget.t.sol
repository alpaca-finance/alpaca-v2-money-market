// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { AV_BaseTest, console } from "./AV_BaseTest.t.sol";

// interfaces
import { IAVRebalanceFacet } from "../../contracts/automated-vault/interfaces/IAVRebalanceFacet.sol";

// libraries
import { LibAV01 } from "../../contracts/automated-vault/libraries/LibAV01.sol";

contract AV_Rebalance_RetargetTest is AV_BaseTest {
  function setUp() public override {
    super.setUp();

    address[] memory _rebalancers = new address[](1);
    _rebalancers[0] = address(this);
    adminFacet.setRebalancersOk(_rebalancers, true);
  }

  function testCorrectness_WhenRebalancerCallRetarget_WhileDeltaDebtPositive_ShouldIncreaseDebtToMatchTarget()
    external
  {
    vm.prank(ALICE);
    tradeFacet.deposit(address(avShareToken), 1 ether, 0);

    // increase lp price to make deltaDebt positive
    // original lp price = 2
    mockOracle.setLpTokenPrice(address(wethUsdcLPToken), 3 ether);

    // TODO: assert debt before

    rebalanceFacet.retarget(address(avShareToken));

    // TODO: assert debt after
  }

  function testCorrectness_WhenRebalancerCallRetarget_WhileDeltaDebtNegative_ShouldDecreaseDebtToMatchTarget()
    external
  {
    /**
     * scenario
     *
     * 1. ALICE deposit 1 usdc at 3x leverage, vault borrow 0.5 usdc, 1.5 weth to farm 1.5 lp
     *      - debtValue = 0.5 * 1 - 1.5 * 1 = 2 usd
     *
     * 2. lp price decrease to 1.8 usd, vault can be retargeted
     *      - equity = lpValue - debtValue = 1.5 * 1.8 - 2 = 0.7 usd
     *      - deltaDebt = currentEquity * (leverage - 1) - currentDebt = 0.7 * (3 - 1) - 2 = -0.6
     *
     * 3. perform retarget
     *      - withdraw lp value of 0.6 usd, get 0.3 usdc, 0.3 weth
     *      - repay 0.3 usdc, 0.3 weth debt
     */
    vm.prank(ALICE);
    tradeFacet.deposit(address(avShareToken), 1 ether, 0);

    // decrease lp price to make deltaDebt negative
    // original lp price = 2
    mockOracle.setLpTokenPrice(address(wethUsdcLPToken), 1.8 ether);
    mockRouter.setRemoveLiquidityAmountsOut(0.3 ether, 0.3 ether);

    // TODO: assert debt before

    rebalanceFacet.retarget(address(avShareToken));

    // TODO: assert debt after
  }

  function testRevert_WhenNonRebalancerCallRetarget() external {
    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(IAVRebalanceFacet.AVRebalanceFacet_Unauthorized.selector, ALICE));
    rebalanceFacet.retarget(address(avShareToken));
  }
}
