// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, console } from "./LYF_BaseTest.t.sol";

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
    uint256 collatToRepurchase = (debtToRepurchase * 1e18) / collatUSDPrice;
    result = (collatToRepurchase * (10000 + REPURCHASE_REWARD_BPS)) / 10000;
  }

  function testCorrectness_WhenLYFRepurchase_ShouldWork() external {
    /**
     * scenario:
     *
     * 1. @ 1 usdc/weth: alice add collateral 40 weth, open farm with 30 weth, 30 usdc
     *      - 30 weth collateral is used to open position -> 10 weth left as collateral
     *      - alice need to borrow 30 usdc
     * 2. price drops to 0.8 usdc/weth -> position become repurchaseable
     *
     * 3. bob repurchase weth collateral with 5 usdc, bob will receive 6.3125 weth
     *      - 5 / 0.8 = 6.25 weth will be repurchased by bob
     *      - 6.25 * 1% = 0.0625 weth as repurchase reward for bob
     *
     * 4. alice position after repurchase
     *      - alice subaccount 0 weth collateral = 10 - 6.3125 = 3.6875 weth
     *      - alice subaccount 0 usdc debt = 30 - 5 = 25 usdc
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

    chainLinkOracle.add(address(weth), address(usd), 0.8 ether, block.timestamp);

    vm.prank(BOB);
    liquidationFacet.repurchase(ALICE, subAccount0, _debtToken, _collatToken, _lpToken, _amountToRepurchase);

    // check bob balance
    uint256 _bobWethReceivedFromRepurchase = _calcCollatRepurchaserShouldReceive(_amountToRepurchase, 0.8 ether);
    assertEq(weth.balanceOf(BOB) - _bobWethBalanceBefore, _bobWethReceivedFromRepurchase);
    assertEq(_bobUsdcBalanceBefore - usdc.balanceOf(BOB), _amountToRepurchase);

    // check alice position
    assertEq(
      collateralFacet.subAccountCollatAmount(_aliceSubAccount0, _collatToken),
      10 ether - _bobWethReceivedFromRepurchase // TODO: account for repurchase fee
    );
    (, uint256 _aliceUsdcDebtValue) = farmFacet.getDebt(ALICE, subAccount0, address(usdc), _lpToken);
    assertEq(_aliceUsdcDebtValue, 25 ether);
  }
}
