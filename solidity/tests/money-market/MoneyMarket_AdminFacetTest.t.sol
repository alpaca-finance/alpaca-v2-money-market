// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, console } from "./MoneyMarket_BaseTest.t.sol";

// interfaces
import { IAdminFacet, LibMoneyMarket01 } from "../../contracts/money-market/facets/AdminFacet.sol";

contract MoneyMarket_AdminFacetTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testRevert_FailedSanityCheck() external {
    // address 0
    vm.expectRevert();
    adminFacet.setInterestModel(address(weth), address(0));

    vm.expectRevert();
    adminFacet.setNonCollatInterestModel(ALICE, address(weth), address(0));

    vm.expectRevert();
    adminFacet.setOracle(address(0));

    // wrong contract
    vm.expectRevert();
    adminFacet.setInterestModel(address(weth), address(btc));

    vm.expectRevert();
    adminFacet.setNonCollatInterestModel(ALICE, address(weth), address(btc));

    vm.expectRevert();
    adminFacet.setOracle(address(btc));
  }
}
