// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest, console } from "../MoneyMarket_BaseTest.t.sol";

// interfaces
import { IAdminFacet } from "../../../contracts/money-market/interfaces/IAdminFacet.sol";

contract MoneyMarket_Admin_SetMaxNumberOfTokenTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenLYFAdminSetMaxNumOfToken_ShouldCorrect() external {
    (uint8 _maxNumOfCollatBefore, uint8 _maxNumOfDebtBefore, uint8 _maxNumOfNonColaltDebtBefore) = viewFacet
      .getMaxNumOfToken();
    // 3 is set from basetest
    assertEq(_maxNumOfCollatBefore, 3);
    assertEq(_maxNumOfDebtBefore, 3);
    assertEq(_maxNumOfNonColaltDebtBefore, 3);
    adminFacet.setMaxNumOfToken(4, 5, 6);

    (uint8 _maxNumOfCollatAfter, uint8 _maxNumOfDebtAfter, uint8 _maxNumOfNonColaltDebtAfter) = viewFacet
      .getMaxNumOfToken();
    assertEq(_maxNumOfCollatAfter, 4);
    assertEq(_maxNumOfDebtAfter, 5);
    assertEq(_maxNumOfNonColaltDebtAfter, 6);
  }
}
