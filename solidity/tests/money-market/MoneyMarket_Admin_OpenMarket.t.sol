// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { IAdminFacet } from "../../contracts/money-market/interfaces/IAdminFacet.sol";
import { IERC20 } from "../../contracts/money-market/interfaces/IERC20.sol";

contract MoneyMarket_Admin_OpenMarketTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenUserOpenNewMarket_ShouldOpenOncePerToken() external {
    // should pass when register new token
    address _ibToken = adminFacet.openMarket(address(opm));
    assertEq(IERC20(_ibToken).name(), "Interest Bearing OPM");
    assertEq(IERC20(_ibToken).symbol(), "ibOPM");
    assertEq(IERC20(_ibToken).decimals(), 9);

    vm.expectRevert(abi.encodeWithSelector(IAdminFacet.AdminFacet_InvalidToken.selector, address(opm)));
    adminFacet.openMarket(address(opm));

    // able to deposit
    vm.prank(ALICE);
    lendFacet.deposit(address(opm), normalizeEther(5 ether, opmDecimal));
    assertEq(IERC20(_ibToken).balanceOf(ALICE), normalizeEther(5 ether, IERC20(_ibToken).decimals()));
  }
}
