// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { ILendFacet } from "../../contracts/money-market/facets/LendFacet.sol";
import { IERC20 } from "../../contracts/money-market/interfaces/IERC20.sol";

contract MoneyMarket_Lend_OpenMarketTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenUserOpenNewMarket_ShouldOpenOncePerToken() external {
    vm.startPrank(ALICE);
    // should pass when register new token
    address _ibToken = lendFacet.openMarket(address(opm));
    assertEq(IERC20(_ibToken).name(), "Interest Bearing OPM");
    assertEq(IERC20(_ibToken).symbol(), "ibOPM");
    assertEq(IERC20(_ibToken).decimals(), 9);

    vm.expectRevert(abi.encodeWithSelector(ILendFacet.LendFacet_InvalidToken.selector, address(opm)));
    lendFacet.openMarket(address(opm));

    // able to deposit
    lendFacet.deposit(address(opm), 5 ether);
    assertEq(IERC20(_ibToken).balanceOf(ALICE), 5 ether);
    vm.stopPrank();
  }
}
