// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { AV_BaseTest, console, MockInterestModel, IAVVaultToken } from "./AV_BaseTest.t.sol";

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

    address[] memory _operators = new address[](1);
    _operators[0] = address(this);
    adminFacet.setOperatorsOk(_operators, true);

    _vaultToken = address(vaultToken);
    _lpToken = address(usdcWethLPToken);
  }

  function testCorrectness_WhenAVRetarget_WhileDeltaDebtPositive_ShouldIncreaseDebtToMatchTarget() external {
    /**
     * scenario
     *
     * 1) ALICE deposit 1 usdc at 3x leverage, vault borrow 0.5 usdc, 1.5 weth to farm 1.5 lp
     *    - debtValue = 0.5 * 1 + 1.5 * 1 = 2 usd
     *
     * 2) lp profit and value increased to 3.6 usd, vault can be retargeted
     *    - equity = newLPValue - debtValue = 3.6 - 2 = 1.6 usd
     *    - deltaDebt = currentEquity * (leverage - 1) - currentDebt = 1.6 * (3 - 1) - 2 = 1.2
     *
     * 3) perform retarget
     *    - borrow usdc = deltaDebt / 2 = 1.2 / 2 = 0.6 usdc
     *    - borrow weth = deltaDebt - usdc borrow value = 1.2 - 0.6 = 0.6
     */

    // 1)
    vm.prank(ALICE);
    tradeFacet.deposit(_vaultToken, normalizeEther(1 ether, usdcDecimal), 0);

    // 2)
    // ALICE has 1.5 lp, price = 2.4 would make total lp value = 1.5 * 2.4 = 3.6 usd
    mockOracle.setLpTokenPrice(_lpToken, 2.4 ether);

    // 3)
    rebalanceFacet.retarget(_vaultToken);

    // check debt after retarget should increase
    (uint256 _stableDebt, uint256 _assetDebt) = viewFacet.getDebtValues(_vaultToken);
    assertEq(_stableDebt, normalizeEther(0.5 ether + 0.6 ether, usdcDecimal));
    assertEq(_assetDebt, 1.5 ether + 0.6 ether);
  }

  function testCorrectness_WhenAVRetarget_WhileDeltaDebtPositiveWithPrecisionLoss_ShouldIncreaseDebtToMatchTarget()
    external
  {
    MockInterestModel mockInterestModel1 = new MockInterestModel(0);
    MockInterestModel mockInterestModel2 = new MockInterestModel(0);
    address _newVaultToken = address(
      IAVVaultToken(
        adminFacet.openVault(
          address(usdcWethLPToken),
          address(usdc),
          address(weth),
          address(handler),
          4,
          0,
          address(mockInterestModel1),
          address(mockInterestModel2)
        )
      )
    );

    // don't ask where these numbers come from it just happened to make
    // deltaDebt last decimal digit odd number and cause precision loss during stableBorrowAmount calculation
    // deltaDebt = 0.666666333333333324
    // stableBorrowValue and Amount = 0.333333
    // assetBorrowValue and Amount = 0.333333166666666662
    vm.prank(ALICE);
    tradeFacet.deposit(_newVaultToken, normalizeEther(1.999999 ether, usdcDecimal), 0);

    mockOracle.setLpTokenPrice(_lpToken, 2.055555555555555555 ether);

    rebalanceFacet.retarget(_newVaultToken);

    // check debt after retarget should increase
    (uint256 _stableDebt, uint256 _assetDebt) = viewFacet.getDebtValues(_newVaultToken);
    assertEq(_stableDebt, 1999999 + 333333);
    assertEq(_assetDebt, 1.999999 ether * 2 + 0.333333166666666662 ether);
  }

  function testCorrectness_WhenAVRetarget_WhileDeltaDebtNegative_ShouldDecreaseDebtToMatchTarget() external {
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
    tradeFacet.deposit(_vaultToken, normalizeEther(1 ether, usdcDecimal), 0);

    // 2)
    // ALICE has 1.5 lp, price = 1.8 would make total lp value = 1.5 * 1.8 = 2.7 usd
    mockOracle.setLpTokenPrice(_lpToken, 1.8 ether);
    mockRouter.setRemoveLiquidityAmountsOut(normalizeEther(0.3 ether, usdcDecimal), 0.3 ether);

    rebalanceFacet.retarget(_vaultToken);

    // check debt after retarget should decrease
    (uint256 _stableDebt, uint256 _assetDebt) = viewFacet.getDebtValues(_vaultToken);
    assertEq(_stableDebt, normalizeEther(0.2 ether, usdcDecimal));
    assertEq(_assetDebt, 1.5 ether - 0.3 ether);
  }

  // TODO: handle case where withdraw more than debt
  // function testCorrectness_WhenAVRetarget_WhileDeltaDebtNegative_WithdrawMoreThanDebtOneSide_ShouldDOWHAT()
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

  function testCorrectness_WhenAVRetarget_WhileDeltaDebtEqualToTarget_DebtShouldNotChange() external {
    vm.prank(ALICE);
    tradeFacet.deposit(_vaultToken, normalizeEther(1 ether, usdcDecimal), 0);

    (uint256 _stableDebtBefore, uint256 _assetDebtBefore) = viewFacet.getDebtValues(_vaultToken);

    vm.expectEmit(true, false, false, false, avDiamond);
    emit LogRetarget(_vaultToken, normalizeEther(1 ether, usdcDecimal), 1 ether);
    rebalanceFacet.retarget(_vaultToken);

    // check debt after retarget should not change
    (uint256 _stableDebtAfter, uint256 _assetDebtAfter) = viewFacet.getDebtValues(_vaultToken);
    assertEq(_stableDebtBefore, _stableDebtAfter);
    assertEq(_assetDebtBefore, _assetDebtAfter);
  }

  function testCorrectness_WhenAVRetarget_ShouldAccrueInterestAndMintManagementFee() external {
    vm.prank(ALICE);
    tradeFacet.deposit(_vaultToken, normalizeEther(1 ether, usdcDecimal), 0);

    rebalanceFacet.retarget(_vaultToken);

    // should accrue interest
    assertEq(viewFacet.getLastAccrueInterestTimestamp(_vaultToken), block.timestamp);
    (uint256 _stablePendingInterest, uint256 _assetPendingInterest) = viewFacet.getPendingInterest(_vaultToken);
    assertEq(_stablePendingInterest, 0);
    assertEq(_assetPendingInterest, 0);
    // should mint management fee
    assertEq(viewFacet.getPendingManagementFee(_vaultToken), 0);
  }

  function testRevert_WhenNonOperatorCallAVRetarget() external {
    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(IAVRebalanceFacet.AVRebalanceFacet_Unauthorized.selector, ALICE));
    rebalanceFacet.retarget(_vaultToken);
  }
}
