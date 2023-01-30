// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

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
    uint256 _amountToRepay = 0.1 ether;

    vm.prank(ALICE);
    tradeFacet.deposit(_vaultToken, 1 ether, 0);

    uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);
    uint256 _bobWethBalanceBefore = weth.balanceOf(BOB);

    vm.prank(BOB);
    rebalanceFacet.repurchase(_vaultToken, _tokenToRepay, _amountToRepay);

    uint256 _amountRepurchaserShouldRecieved = (_amountToRepay * (10000 + _repurchaseRewardBps)) / 10000;

    // check BOB balances
    assertEq(_bobUsdcBalanceBefore - usdc.balanceOf(BOB), _amountToRepay);
    assertEq(weth.balanceOf(BOB) - _bobWethBalanceBefore, _amountRepurchaserShouldRecieved);

    // check vault debts
    (uint256 _stableDebt, uint256 _assetDebt) = viewFacet.getDebtValues(_vaultToken);
    assertEq(_stableDebt, 0.5 ether - _amountToRepay);
    assertEq(_assetDebt, 1.5 ether + _amountRepurchaserShouldRecieved);
  }

  function testCorrectness_WhenAVRepurchaseToRepayAsset_ShouldRepayAssetBorrowStableAndPayRewardToCaller() external {
    address _tokenToRepay = address(weth);
    uint256 _amountToRepay = 0.1 ether;

    vm.prank(ALICE);
    tradeFacet.deposit(_vaultToken, 1 ether, 0);

    uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);
    uint256 _bobWethBalanceBefore = weth.balanceOf(BOB);

    vm.prank(BOB);
    rebalanceFacet.repurchase(_vaultToken, _tokenToRepay, _amountToRepay);

    uint256 _amountRepurchaserShouldRecieved = (_amountToRepay * (10000 + _repurchaseRewardBps)) / 10000;

    // check BOB balances
    assertEq(usdc.balanceOf(BOB) - _bobUsdcBalanceBefore, _amountRepurchaserShouldRecieved);
    assertEq(_bobWethBalanceBefore - weth.balanceOf(BOB), _amountToRepay);

    // check vault debts
    (uint256 _stableDebt, uint256 _assetDebt) = viewFacet.getDebtValues(_vaultToken);
    assertEq(_stableDebt, 0.5 ether + _amountRepurchaserShouldRecieved);
    assertEq(_assetDebt, 1.5 ether - _amountToRepay);
  }

  function testCorrectness_WhenAVRepurchase_ShouldAccrueInterestAndMintManagementFee() external {
    vm.prank(ALICE);
    tradeFacet.deposit(_vaultToken, 1 ether, 0);

    vm.prank(BOB);
    rebalanceFacet.repurchase(_vaultToken, address(usdc), 0.1 ether);

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
