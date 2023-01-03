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
    lendFacet.deposit(address(usdc), 100 ether);

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 2 ether);
    borrowFacet.borrow(subAccount0, address(usdc), 1 ether);
    collateralFacet.addCollateral(ALICE, subAccount1, address(weth), 10 ether);
    borrowFacet.borrow(subAccount1, address(usdc), 2 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenAdminWriteOffSubAccountsDebt_DebtShouldBeZero() external {
    /**
     * starting condition
     *
     * on ALICE subaccount0
     *  - add 2 weth as collateral
     *  - borrow 1 usdc
     *
     * on ALICE subaccount1
     *  - add 10 weth as collateral
     *  - borrow 2 usdc
     *
     * 1 weth = 1 usdc
     */

    address _debtToken = address(usdc);

    // make both subaccount unhealthy
    mockOracle.setTokenPrice(address(weth), 0.1 ether);

    uint256 _subAccount0DebtAmount;
    (, _subAccount0DebtAmount) = viewFacet.getOverCollatSubAccountDebt(ALICE, subAccount0, _debtToken);
    assertEq(_subAccount0DebtAmount, 1 ether);

    uint256 _subAccount1DebtAmount;
    (, _subAccount1DebtAmount) = viewFacet.getOverCollatSubAccountDebt(ALICE, subAccount1, _debtToken);
    assertEq(_subAccount1DebtAmount, 2 ether);

    assertEq(viewFacet.getGlobalDebtValue(_debtToken), 3 ether);
    assertEq(viewFacet.getOverCollatDebtValue(_debtToken), 3 ether);
    assertEq(viewFacet.getOverCollatTokenDebtShares(_debtToken), 3 ether);

    // write off both subaccount debt
    IAdminFacet.WriteOffSubAccountDebtInput[] memory _inputs = new IAdminFacet.WriteOffSubAccountDebtInput[](2);
    _inputs[0] = IAdminFacet.WriteOffSubAccountDebtInput(ALICE, subAccount0, _debtToken);
    _inputs[1] = IAdminFacet.WriteOffSubAccountDebtInput(ALICE, subAccount1, _debtToken);

    vm.expectEmit(true, true, false, false, moneyMarketDiamond);
    emit LogWriteOffSubAccountDebt(viewFacet.getSubAccount(ALICE, subAccount0), _debtToken, 1 ether, 1 ether);
    vm.expectEmit(true, true, false, false, moneyMarketDiamond);
    emit LogWriteOffSubAccountDebt(viewFacet.getSubAccount(ALICE, subAccount1), _debtToken, 2 ether, 2 ether);
    adminFacet.writeOffSubAccountsDebt(_inputs);

    // check subaccounts debt, no debt remain
    (, _subAccount0DebtAmount) = viewFacet.getOverCollatSubAccountDebt(ALICE, subAccount0, _debtToken);
    assertEq(_subAccount0DebtAmount, 0);

    (, _subAccount1DebtAmount) = viewFacet.getOverCollatSubAccountDebt(ALICE, subAccount1, _debtToken);
    assertEq(_subAccount1DebtAmount, 0);

    // check diamond debt states, no debt remain
    assertEq(viewFacet.getGlobalDebtValue(_debtToken), 0);
    assertEq(viewFacet.getOverCollatDebtValue(_debtToken), 0);
    assertEq(viewFacet.getOverCollatTokenDebtShares(_debtToken), 0);
  }

  function testRevert_WhenAdminWriteOffSubAccountsDebt_ButOneSubAccountIsHealthy() external {
    // make subaccount0 unhealthy while subaccount1 still healthy
    mockOracle.setTokenPrice(address(weth), 0.4 ether);

    IAdminFacet.WriteOffSubAccountDebtInput[] memory _inputs = new IAdminFacet.WriteOffSubAccountDebtInput[](2);
    _inputs[0] = IAdminFacet.WriteOffSubAccountDebtInput(ALICE, subAccount0, address(usdc));
    _inputs[1] = IAdminFacet.WriteOffSubAccountDebtInput(ALICE, subAccount1, address(usdc));

    // should revert since subaccount1 is healthy
    vm.expectRevert(
      abi.encodeWithSelector(
        IAdminFacet.AdminFacet_SubAccountHealthy.selector,
        viewFacet.getSubAccount(ALICE, subAccount1)
      )
    );
    adminFacet.writeOffSubAccountsDebt(_inputs);
  }

  function testRevert_WhenNonAdminWriteOffSubAccountDebt() external {
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    IAdminFacet.WriteOffSubAccountDebtInput[] memory _inputs = new IAdminFacet.WriteOffSubAccountDebtInput[](1);
    _inputs[0] = IAdminFacet.WriteOffSubAccountDebtInput(ALICE, subAccount0, address(usdc));
    adminFacet.writeOffSubAccountsDebt(_inputs);
  }
}
