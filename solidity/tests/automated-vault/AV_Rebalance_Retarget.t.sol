// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { AV_BaseTest, console } from "./AV_BaseTest.t.sol";

// interfaces
import { IAVRebalanceFacet } from "../../contracts/automated-vault/interfaces/IAVRebalanceFacet.sol";

// libraries
import { LibAV01 } from "../../contracts/automated-vault/libraries/LibAV01.sol";

contract AV_Rebalance_RetargetTest is AV_BaseTest {
  event LogRetarget(address indexed _vaultToken, uint256 _equityBefore, uint256 _equityAfter);

  address internal _vaultToken;
  address internal _lpToken;

  function setUp() public override {
    super.setUp();

    address[] memory _rebalancers = new address[](1);
    _rebalancers[0] = address(this);
    adminFacet.setRebalancersOk(_rebalancers, true);

    _vaultToken = address(avShareToken);
    _lpToken = address(wethUsdcLPToken);
  }

  function testCorrectness_WhenRebalancerCallRetarget_WhileDeltaDebtPositive_ShouldIncreaseDebtToMatchTarget()
    external
  {
    /**
     * scenario
     *
     * 1) ALICE deposit 1 usdc at 3x leverage, vault borrow 0.5 usdc, 1.5 weth to farm 1.5 lp
     *    - debtValue = 0.5 * 1 + 1.5 * 1 = 2 usd
     *
     * 2) lp profit and value increased, 1 lp = 1.8 weth + 1.8 usdc, vault can be retargeted
     *    - newLPValue = 1.8 * 1 + 1.8 * 1 = 3.6 usd
     *    - equity = newLPValue - debtValue = 3.6 - 2 = 1.6 usd
     *    - deltaDebt = currentEquity * (leverage - 1) - currentDebt = 1.6 * (3 - 1) - 2 = 1.2
     *
     * 3) perform retarget
     *    - borrow usd value = deltaDebt / 2 = 0.6 usd
     *    - borrow 0.6 usdc
     *    - borrow 0.6 weth
     */

    // 1)
    vm.prank(ALICE);
    tradeFacet.deposit(_vaultToken, 1 ether, 0);

    // 2)
    // ALICE has 1.5 lp, price = 2.4 would make total lp value = 1.5 * 2.4 = 3.6 usd
    mockOracle.setLpTokenPrice(_lpToken, 2.4 ether);

    // TODO: assert debt before

    // 3)
    rebalanceFacet.retarget(_vaultToken);

    // TODO: assert debt after
  }

  function testCorrectness_WhenRebalancerCallRetarget_WhileDeltaDebtNegative_ShouldDecreaseDebtToMatchTarget()
    external
  {
    /**
     * scenario
     *
     * 1) ALICE deposit 1 usdc at 3x leverage, vault borrow 0.5 usdc, 1.5 weth to farm 1.5 lp
     *    - debtValue = 0.5 * 1 + 1.5 * 1 = 2 usd
     *
     * 2) lp rekt and value decreased, 1 lp = 1.35 usdc + 1.35 weth, vault can be retargeted
     *    - newLPValue = 1.35 * 1 + 1.35 * 1 = 2.7 usd
     *    - equity = newLPValue - debtValue = 2.7 - 2 = 0.7 usd
     *    - deltaDebt = currentEquity * (leverage - 1) - currentDebt = 0.7 * (3 - 1) - 2 = -0.6
     *
     * 3) perform retarget
     *    - withdraw lp value of 0.6 usd, get 0.3 usdc, 0.3 weth
     *    - repay 0.3 usdc, 0.3 weth debt
     */

    // 1)
    vm.prank(ALICE);
    tradeFacet.deposit(_vaultToken, 1 ether, 0);

    // 2)
    // ALICE has 1.5 lp, price = 1.8 would make total lp value = 1.5 * 1.8 = 2.4 usd
    mockOracle.setLpTokenPrice(_lpToken, 1.8 ether);
    mockRouter.setRemoveLiquidityAmountsOut(0.3 ether, 0.3 ether);

    // TODO: assert debt before

    rebalanceFacet.retarget(_vaultToken);

    // TODO: assert debt after
  }

  // TODO: handle case where withdraw more than debt
  // function testCorrectness_WhenRebalancerCallRetarget_WhileDeltaDebtNegative_WithdrawMoreThanDebtOneSide_ShouldDOWHAT()
  //   external
  // {
  //   /**
  //    * scenario
  //    *
  //    * 1) ALICE deposit 1 usdc at 3x leverage, vault borrow 0.5 usdc, 1.5 weth to farm 1.5 lp
  //    *    - debtValue = 0.5 * 1 + 1.5 * 1 = 2 usd
  //    *
  //    * 2) lp rekt and value decreased, 1 lp = 1.2 usdc + 1.2 weth, vault can be retargeted
  //    *    - newLPValue = 1.2 * 1 + 1.2 * 1 = 2.4 usd
  //    *    - equity = newLPValue - debtValue = 2.4 - 2 = 0.4 usd
  //    *    - deltaDebt = currentEquity * (leverage - 1) - currentDebt = 0.4 * (3 - 1) - 2 = -1.2
  //    *
  //    * 3) perform retarget
  //    *    - withdraw lp value of 1.2 usd, get 0.6 usdc, 0.6 weth
  //    *    - repay 0.6 weth debt
  //    *    - can't repay 0.6 usdc because its more than 0.5 usdc debt
  //    */
  // }

  function testCorrectness_WhenRebalancerCallRetarget_WhileDeltaDebtEqualToTarget_ShouldDoNothing() external {
    vm.prank(ALICE);
    tradeFacet.deposit(_vaultToken, 1 ether, 0);

    vm.expectEmit(true, false, false, false, avDiamond);
    emit LogRetarget(_vaultToken, 1 ether, 1 ether);
    rebalanceFacet.retarget(_vaultToken);
  }

  function testRevert_WhenNonRebalancerCallRetarget() external {
    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(IAVRebalanceFacet.AVRebalanceFacet_Unauthorized.selector, ALICE));
    rebalanceFacet.retarget(_vaultToken);
  }
}
