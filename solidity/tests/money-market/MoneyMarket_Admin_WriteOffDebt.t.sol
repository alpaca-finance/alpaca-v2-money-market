// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { IAdminFacet } from "../../contracts/money-market/interfaces/IAdminFacet.sol";

contract MoneyMarket_Admin_WriteOffDebtTest is MoneyMarket_BaseTest {
  event LogWriteOffSubAccountDebt(
    address indexed subAccount,
    address indexed token,
    uint256 debtShareWrittenOff,
    uint256 debtValueWrittenOff
  );

  function setUp() public override {
    super.setUp();

    vm.prank(BOB);
    lendFacet.deposit(address(weth), 100 ether);
  }

  function testCorrectness_WhenAdminWriteOffSubAccountDebt_DebtShouldBeZero() external {
    address _debtToken = address(weth);

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 10 ether);
    borrowFacet.borrow(subAccount0, _debtToken, 1 ether);
    vm.stopPrank();

    uint256 _subAccountDebtAmount;
    (, _subAccountDebtAmount) = viewFacet.getOverCollatSubAccountDebt(ALICE, subAccount0, _debtToken);
    assertEq(_subAccountDebtAmount, 1 ether);
    assertEq(viewFacet.getGlobalDebtValue(_debtToken), 1 ether);
    assertEq(viewFacet.getOverCollatDebtValue(_debtToken), 1 ether);
    assertEq(viewFacet.getOverCollatTokenDebtShares(_debtToken), 1 ether);

    IAdminFacet.WriteOffSubAccountDebtInput[] memory _inputs = new IAdminFacet.WriteOffSubAccountDebtInput[](1);
    _inputs[0] = IAdminFacet.WriteOffSubAccountDebtInput(ALICE, subAccount0, _debtToken);

    vm.expectEmit(true, true, false, false, moneyMarketDiamond);
    emit LogWriteOffSubAccountDebt(viewFacet.getSubAccount(ALICE, subAccount0), _debtToken, 1 ether, 1 ether);
    adminFacet.writeOffSubAccountsDebt(_inputs);

    (, _subAccountDebtAmount) = viewFacet.getOverCollatSubAccountDebt(ALICE, subAccount0, _debtToken);
    assertEq(_subAccountDebtAmount, 0);
    assertEq(viewFacet.getGlobalDebtValue(_debtToken), 0);
    assertEq(viewFacet.getOverCollatDebtValue(_debtToken), 0);
    assertEq(viewFacet.getOverCollatTokenDebtShares(_debtToken), 0);
  }

  function testRevert_WhenNonAdminWriteOffSubAccountDebt() external {
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    IAdminFacet.WriteOffSubAccountDebtInput[] memory _inputs = new IAdminFacet.WriteOffSubAccountDebtInput[](1);
    _inputs[0] = IAdminFacet.WriteOffSubAccountDebtInput(ALICE, subAccount0, address(weth));
    adminFacet.writeOffSubAccountsDebt(_inputs);
  }
}
