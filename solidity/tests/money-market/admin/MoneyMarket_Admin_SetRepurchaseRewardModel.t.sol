// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest } from "../MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { IAdminFacet } from "../../../contracts/money-market/interfaces/IAdminFacet.sol";
import { FixedFeeModel100Bps, IFeeModel } from "../../../contracts/money-market/fee-models/FixedFeeModel100Bps.sol";

contract MoneyMarket_Admin_SetRepurchaseRewardModelTest is MoneyMarket_BaseTest {
  FixedFeeModel100Bps fixedFeeModel;

  function setUp() public override {
    super.setUp();

    fixedFeeModel = new FixedFeeModel100Bps();
  }

  function testCorrectness_WhenAdminSetRepurchaseRewardModel_ShouldWork() external {
    adminFacet.setRepurchaseRewardModel(fixedFeeModel);

    assertEq(viewFacet.getRepurchaseRewardModel(), address(fixedFeeModel));
  }

  function testRevert_WhenNonOwnerCallSetRepurchaseRewardModel_ShouldRevert() external {
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setRepurchaseRewardModel(fixedFeeModel);
  }

  function testRevert_WhenRepurchaseRewardModelReturnFeeMoreThanMaxRepurchaseFee_ShouldRevert() external {
    vm.mockCall(
      address(fixedFeeModel),
      abi.encodeWithSelector(FixedFeeModel100Bps.getFeeBps.selector),
      abi.encode(LibMoneyMarket01.MAX_REPURCHASE_FEE_BPS + 1)
    );

    vm.expectRevert(abi.encodeWithSelector(IAdminFacet.AdminFacet_ExceedMaxRepurchaseReward.selector));
    adminFacet.setRepurchaseRewardModel(fixedFeeModel);
  }
}
