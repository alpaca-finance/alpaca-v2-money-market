// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest, MockERC20, console } from "../MoneyMarket_BaseTest.t.sol";
import { DebtToken_BaseTest } from "./DebtToken_BaseTest.t.sol";

// contracts
import { DebtToken } from "../../../contracts/money-market/DebtToken.sol";

contract DebtToken_SetOkHoldersTest is DebtToken_BaseTest {
  DebtToken internal debtToken;
  address[] internal _okHolders;

  function setUp() public override {
    super.setUp();

    debtToken = deployUninitializedDebtToken();
    debtToken.initialize(address(weth), moneyMarketDiamond);

    _okHolders = new address[](1);
    _okHolders[0] = address(moneyMarketDiamond);
  }

  function testCorrectness_WhenSetOkHolders_ShouldWork() external {
    vm.prank(moneyMarketDiamond);
    debtToken.setOkHolders(_okHolders, true);

    assertTrue(debtToken.okHolders(address(moneyMarketDiamond)));
  }

  function testRevert_WhenSetOkHoldersFromNonOwner() external {
    vm.prank(ALICE);
    vm.expectRevert("Ownable: caller is not the owner");
    debtToken.setOkHolders(_okHolders, true);
  }
}
