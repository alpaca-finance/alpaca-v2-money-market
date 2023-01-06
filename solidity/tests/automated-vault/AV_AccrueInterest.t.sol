// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { AV_BaseTest, console } from "./AV_BaseTest.t.sol";

import { LibAV01 } from "../../contracts/automated-vault/libraries/LibAV01.sol";

contract AV_AccrueInterestTest is AV_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenDepositSubsequentlyAndTimePast_InterestShouldIncreaseAndAccrued() external {
    address _vaultToken = address(avShareToken);

    assertEq(tradeFacet.getVaultLastAccrueInterestTimestamp(_vaultToken), 0);

    vm.prank(ALICE);
    tradeFacet.deposit(_vaultToken, 1 ether, 0);

    uint256 _stablePendingInterest;
    uint256 _assetPendingInterest;
    (_stablePendingInterest, _assetPendingInterest) = tradeFacet.getVaultPendingInterest(_vaultToken);
    assertEq(_stablePendingInterest, 0);
    assertEq(_assetPendingInterest, 0);

    uint256 _stableDebtValue;
    uint256 _assetDebtValue;
    (_stableDebtValue, _assetDebtValue) = tradeFacet.getDebtValues(_vaultToken);
    assertEq(_stableDebtValue, 0.5 ether);
    assertEq(_assetDebtValue, 1.5 ether);

    vm.warp(block.timestamp + 1);

    (_stablePendingInterest, _assetPendingInterest) = tradeFacet.getVaultPendingInterest(_vaultToken);
    assertEq(_stablePendingInterest, 0.05 ether);
    assertEq(_assetPendingInterest, 0.075 ether);

    vm.prank(BOB);
    tradeFacet.deposit(_vaultToken, 1 ether, 0);

    assertEq(tradeFacet.getVaultLastAccrueInterestTimestamp(_vaultToken), block.timestamp);

    (_stablePendingInterest, _assetPendingInterest) = tradeFacet.getVaultPendingInterest(_vaultToken);
    assertEq(_stablePendingInterest, 0);
    assertEq(_assetPendingInterest, 0);

    (_stableDebtValue, _assetDebtValue) = tradeFacet.getDebtValues(_vaultToken);
    assertEq(_stableDebtValue, 1 ether + 0.05 ether);
    assertEq(_assetDebtValue, 3 ether + 0.075 ether);

    vm.warp(block.timestamp + 1);

    assertEq(tradeFacet.getVaultLastAccrueInterestTimestamp(_vaultToken), block.timestamp - 1);

    (_stablePendingInterest, _assetPendingInterest) = tradeFacet.getVaultPendingInterest(_vaultToken);
    assertEq(_stablePendingInterest, 0.105 ether);
    assertEq(_assetPendingInterest, 0.15375 ether);

    (_stableDebtValue, _assetDebtValue) = tradeFacet.getDebtValues(_vaultToken);
    assertEq(_stableDebtValue, 1 ether + 0.05 ether);
    assertEq(_assetDebtValue, 3 ether + 0.075 ether);
  }
}
