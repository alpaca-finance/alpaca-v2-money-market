// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { IAdminFacet } from "../../contracts/money-market/interfaces/IAdminFacet.sol";

// mocks
import { MockLiquidationStrategy } from "../mocks/MockLiquidationStrategy.sol";

contract MoneyMarket_Admin_WriteOffDebtTest is MoneyMarket_BaseTest {
  event LogWriteOffSubAccountDebt(
    address indexed subAccount,
    address indexed token,
    uint256 debtShareWrittenOff,
    uint256 debtValueWrittenOff
  );

  MockLiquidationStrategy internal mockLiquidationStrategy;

  function setUp() public override {
    super.setUp();

    // seed mm for ALICE to borrow
    vm.prank(BOB);
    lendFacet.deposit(address(usdc), normalizeEther(100 ether, usdcDecimal));

    // setup liquidationStrategy
    mockLiquidationStrategy = new MockLiquidationStrategy(address(mockOracle));
    usdc.mint(address(mockLiquidationStrategy), normalizeEther(1000 ether, usdcDecimal));

    address[] memory _liquidationStrats = new address[](1);
    _liquidationStrats[0] = address(mockLiquidationStrategy);
    adminFacet.setLiquidationStratsOk(_liquidationStrats, true);

    address[] memory _liquidationCallers = new address[](1);
    _liquidationCallers[0] = address(this);
    adminFacet.setLiquidatorsOk(_liquidationCallers, true);

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
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 2 ether);
    borrowFacet.borrow(subAccount0, address(usdc), normalizeEther(1 ether, usdcDecimal));
    collateralFacet.addCollateral(ALICE, subAccount1, address(weth), 10 ether);
    borrowFacet.borrow(subAccount1, address(usdc), normalizeEther(2 ether, usdcDecimal));
    vm.stopPrank();
  }

  function testCorrectness_WhenAdminWriteOffSubAccountsDebt_DebtShouldBeZero() external {
    address _debtToken = address(usdc);
    address _collatToken = address(weth);

    // get rid of both subaccount collats
    mockOracle.setTokenPrice(address(weth), 0.01 ether);

    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      subAccount0,
      _debtToken,
      _collatToken,
      normalizeEther(100 ether, usdcDecimal),
      0
    );

    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      subAccount1,
      _debtToken,
      _collatToken,
      normalizeEther(100 ether, usdcDecimal),
      0
    );

    // write off both subaccount debt
    IAdminFacet.WriteOffSubAccountDebtInput[] memory _inputs = new IAdminFacet.WriteOffSubAccountDebtInput[](2);
    _inputs[0] = IAdminFacet.WriteOffSubAccountDebtInput(ALICE, subAccount0, _debtToken);
    _inputs[1] = IAdminFacet.WriteOffSubAccountDebtInput(ALICE, subAccount1, _debtToken);

    vm.expectEmit(true, true, false, false, moneyMarketDiamond);
    emit LogWriteOffSubAccountDebt(
      viewFacet.getSubAccount(ALICE, subAccount0),
      _debtToken,
      normalizeEther(1 ether, usdcDecimal),
      normalizeEther(1 ether, usdcDecimal)
    );
    vm.expectEmit(true, true, false, false, moneyMarketDiamond);
    emit LogWriteOffSubAccountDebt(
      viewFacet.getSubAccount(ALICE, subAccount1),
      _debtToken,
      normalizeEther(2 ether, usdcDecimal),
      normalizeEther(2 ether, usdcDecimal)
    );
    adminFacet.writeOffSubAccountsDebt(_inputs);

    // check subaccounts debt, no debt remain
    (, uint256 _subAccount0DebtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, subAccount0, _debtToken);
    assertEq(_subAccount0DebtAmount, 0);

    (, uint256 _subAccount1DebtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, subAccount1, _debtToken);
    assertEq(_subAccount1DebtAmount, 0);

    // check diamond debt states, no debt remain
    assertEq(viewFacet.getGlobalDebtValue(_debtToken), 0);
    assertEq(viewFacet.getOverCollatTokenDebtValue(_debtToken), 0);
    assertEq(viewFacet.getOverCollatTokenDebtShares(_debtToken), 0);
  }

  function testRevert_WhenAdminWriteOffSubAccountsDebt_ButOneSubAccountIsHealthy() external {
    address _debtToken = address(usdc);
    address _collatToken = address(weth);

    // make subaccount0 unhealthy while subaccount1 still healthy
    mockOracle.setTokenPrice(address(weth), 0.2 ether);

    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      subAccount0,
      _debtToken,
      _collatToken,
      normalizeEther(100 ether, usdcDecimal),
      0
    );

    IAdminFacet.WriteOffSubAccountDebtInput[] memory _inputs = new IAdminFacet.WriteOffSubAccountDebtInput[](2);
    _inputs[0] = IAdminFacet.WriteOffSubAccountDebtInput(ALICE, subAccount0, _debtToken);
    _inputs[1] = IAdminFacet.WriteOffSubAccountDebtInput(ALICE, subAccount1, _debtToken);

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
