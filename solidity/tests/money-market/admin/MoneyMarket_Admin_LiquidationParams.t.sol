// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest } from "../MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../../contracts/money-market/libraries/LibMoneyMarket01.sol";
import { LibConstant } from "../../../contracts/money-market/libraries/LibConstant.sol";

// interfaces
import { IAdminFacet } from "../../../contracts/money-market/interfaces/IAdminFacet.sol";

contract MoneyMarket_Admin_LiquidationParamsTest is MoneyMarket_BaseTest {
  event LogSetLiquidationParams(uint16 _newMaxLiquidateBps, uint16 _newLiquidationThreshold);

  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenAdminSetLiquidationParams_ShouldWork() external {
    uint16 _maxLiquidateBps = 5000;
    uint16 _liquidationThresholdBps = 11111;

    vm.expectEmit(false, false, false, false, moneyMarketDiamond);
    emit LogSetLiquidationParams(_maxLiquidateBps, _liquidationThresholdBps);
    adminFacet.setLiquidationParams(_maxLiquidateBps, _liquidationThresholdBps);

    (uint16 _actualMaxLiquidateBps, uint16 _actualLiquidationThresholdBps) = viewFacet.getLiquidationParams();

    assertEq(_maxLiquidateBps, _actualMaxLiquidateBps);
    assertEq(_liquidationThresholdBps, _actualLiquidationThresholdBps);
  }

  function testRevert_WhenAdminSetLiquidationParamsExceedMaxBps() external {
    vm.expectRevert(IAdminFacet.AdminFacet_InvalidArguments.selector);
    adminFacet.setLiquidationParams(uint16(LibConstant.MAX_BPS + 1), 0);

    vm.expectRevert(IAdminFacet.AdminFacet_InvalidArguments.selector);
    adminFacet.setLiquidationParams(0, uint16(LibConstant.MAX_BPS - 1));
  }

  function testRevert_WhenNonAdminSetLiquidationParams() external {
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setLiquidationParams(5000, 5000);
  }
}
