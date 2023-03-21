// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { AV_BaseTest, console } from "./AV_BaseTest.t.sol";

// interfaces
import { IAVRebalanceFacet } from "../../contracts/automated-vault/interfaces/IAVRebalanceFacet.sol";

// libraries
import { LibAV01 } from "../../contracts/automated-vault/libraries/LibAV01.sol";

contract AV_Rebalance_RepurchaseTest is AV_BaseTest {
  address internal _vaultToken;
  uint16 internal _repurchaseRewardBps;

  function setUp() public override {
    super.setUp();

    // set repurchaseRewardBps
    _repurchaseRewardBps = 100;
    adminFacet.setRepurchaseRewardBps(_repurchaseRewardBps);

    // whitelist BOB as repurchaser
    address[] memory _repurchasers = new address[](1);
    _repurchasers[0] = BOB;
    adminFacet.setRepurchasersOk(_repurchasers, true);

    _vaultToken = address(vaultToken);
  }

  function testCorrectness_WhenAVRepurchaseToRepayStable_ShouldRepayStableBorrowAssetAndPayRewardToCaller() external {
    address _tokenToRepay = address(usdc);
    uint256 _amountToRepay = normalizeEther(0.1 ether, usdcDecimal);

    vm.prank(ALICE);
    tradeFacet.deposit(_vaultToken, normalizeEther(1 ether, usdcDecimal), 0);

    uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);
    uint256 _bobWethBalanceBefore = weth.balanceOf(BOB);

    vm.prank(BOB);
    rebalanceFacet.repurchase(_vaultToken, _tokenToRepay, _amountToRepay);

    // repay 0.1 usdc, with reward 1%, should receive weth as 0.101 usdc
    // to convert 0.101 usdc * 1 usd / 1 usd = 0.101 weth
    uint256 _amountRepurchaserShouldRecieved = 0.101 ether;

    // check BOB balances
    assertEq(_bobUsdcBalanceBefore - usdc.balanceOf(BOB), _amountToRepay, "usdc balance");
    assertEq(weth.balanceOf(BOB) - _bobWethBalanceBefore, _amountRepurchaserShouldRecieved, "weth balance");

    // check vault debts
    (uint256 _stableDebt, uint256 _assetDebt) = viewFacet.getDebtValues(_vaultToken);
    assertEq(_stableDebt, normalizeEther(0.5 ether, usdcDecimal) - _amountToRepay, "usdc debt");
    assertEq(_assetDebt, 1.5 ether + _amountRepurchaserShouldRecieved, "weth debt");
  }

  function testCorrectness_WhenAVRepurchaseToRepayAsset_ShouldRepayAssetBorrowStableAndPayRewardToCaller() external {
    address _tokenToRepay = address(weth);
    uint256 _amountToRepay = 0.1 ether;

    vm.prank(ALICE);
    tradeFacet.deposit(_vaultToken, normalizeEther(1 ether, usdcDecimal), 0);

    uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);
    uint256 _bobWethBalanceBefore = weth.balanceOf(BOB);

    vm.prank(BOB);
    rebalanceFacet.repurchase(_vaultToken, _tokenToRepay, _amountToRepay);

    // repay 0.1 weth, with reward 1%, should receive usdc as 0.101 weth
    // to convert 0.101 weth * 1 usd / 1 usd = 0.101 usdc
    uint256 _amountRepurchaserShouldRecieved = normalizeEther(0.101 ether, usdcDecimal);

    // check BOB balances
    assertEq(usdc.balanceOf(BOB) - _bobUsdcBalanceBefore, _amountRepurchaserShouldRecieved);
    assertEq(_bobWethBalanceBefore - weth.balanceOf(BOB), _amountToRepay);

    // check vault debts
    (uint256 _stableDebt, uint256 _assetDebt) = viewFacet.getDebtValues(_vaultToken);
    assertEq(_stableDebt, normalizeEther(0.5 ether, usdcDecimal) + _amountRepurchaserShouldRecieved);
    assertEq(_assetDebt, 1.5 ether - _amountToRepay);
  }

  function testCorrectness_WhenAVRepurchase_ShouldAccrueInterestAndMintManagementFee() external {
    vm.prank(ALICE);
    tradeFacet.deposit(_vaultToken, normalizeEther(1 ether, usdcDecimal), 0);

    vm.prank(BOB);
    rebalanceFacet.repurchase(_vaultToken, address(usdc), normalizeEther(0.1 ether, usdcDecimal));

    // should accrue interest
    assertEq(viewFacet.getLastAccrueInterestTimestamp(_vaultToken), block.timestamp);
    // should mint management fee
    assertEq(viewFacet.getPendingManagementFee(_vaultToken), 0);
  }

  function testRevert_WhenAVRepurchaseWithInvalidToken() external {
    address _invalidToken = address(1234);
    vm.prank(BOB);
    vm.expectRevert(abi.encodeWithSelector(IAVRebalanceFacet.AVRebalanceFacet_InvalidToken.selector, _invalidToken));
    rebalanceFacet.repurchase(_vaultToken, _invalidToken, 1 ether);
  }

  function testRevert_WhenNonRepurchaserCallAVRepurchase() external {
    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(IAVRebalanceFacet.AVRebalanceFacet_Unauthorized.selector, ALICE));
    rebalanceFacet.repurchase(_vaultToken, address(usdc), 1 ether);
  }
}
