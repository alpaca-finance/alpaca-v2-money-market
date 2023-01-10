// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { IAdminFacet } from "../../contracts/money-market/interfaces/IAdminFacet.sol";
import { FixedFeeModel, IFeeModel } from "../../contracts/money-market/fee-models/FixedFeeModel.sol";

contract MoneyMarket_Admin_SetRepurchaseFeeModelTest is MoneyMarket_BaseTest {
  FixedFeeModel fixedFeeModel;

  function setUp() public override {
    super.setUp();

    fixedFeeModel = new FixedFeeModel();
  }

  function testCorrectness_WhenAdminSetRepurchaseFeeModel_ShouldWork() external {
    adminFacet.setRepurchaseFeeModel(fixedFeeModel);

    assertEq(viewFacet.getRepurchaseFeeModel(), address(fixedFeeModel));
  }

  function testRevert_WhenNonOwnerCallSetRepurchaseFeeModel_ShouldRevert() external {
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setRepurchaseFeeModel(fixedFeeModel);
  }

  function testRevert_WhenRepurchaseFeeModelReturnFeeMoreThanMaxRepurchaseFee_ShouldRevert() external {
    vm.mockCall(
      address(fixedFeeModel),
      abi.encodeWithSelector(FixedFeeModel.getFeeBps.selector),
      abi.encode(LibMoneyMarket01.MAX_REPURCHASE_FEE_BPS + 1)
    );

    vm.expectRevert(abi.encodeWithSelector(IAdminFacet.AdminFacet_ExceedMaxRepurchaseFee.selector));
    adminFacet.setRepurchaseFeeModel(fixedFeeModel);
  }
}
