// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, console } from "../MoneyMarket_BaseTest.t.sol";

// contracts
import { DebtToken } from "../../../contracts/money-market/DebtToken.sol";

// interfaces
import { IAdminFacet, LibMoneyMarket01 } from "../../../contracts/money-market/facets/AdminFacet.sol";

contract DebtToken_InitializerTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenInitialize_ShouldWork() external {
    DebtToken debtToken = new DebtToken();

    // should revert because haven't set underlying asset via initialize
    vm.expectRevert();
    debtToken.symbol();

    debtToken.initialize(address(weth), moneyMarketDiamond);

    // check properties inherited from underlying
    assertEq(debtToken.symbol(), string.concat("debt", weth.symbol()));
    assertEq(debtToken.name(), string.concat("debt", weth.symbol()));
    assertEq(debtToken.decimals(), weth.decimals());

    // check money market being set correctly
  }
}
