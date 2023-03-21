// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest, MockERC20, console } from "../MoneyMarket_BaseTest.t.sol";
import { DebtToken_BaseTest } from "./DebtToken_BaseTest.t.sol";

// contracts
import { DebtToken } from "../../../contracts/money-market/DebtToken.sol";

contract DebtToken_InitializerTest is DebtToken_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenInitialize_ShouldWork() external {
    DebtToken debtToken = deployUninitializedDebtToken();

    // should revert because haven't set underlying asset via initialize
    vm.expectRevert();
    debtToken.symbol();

    debtToken.initialize(address(weth), moneyMarketDiamond);

    // check properties inherited from underlying
    assertEq(debtToken.symbol(), string.concat("debt", weth.symbol()));
    assertEq(debtToken.name(), string.concat("debt", weth.symbol()));
    assertEq(debtToken.decimals(), weth.decimals());

    // check money market being set correctly
    assertEq(debtToken.owner(), moneyMarketDiamond);
    assertEq(debtToken.moneyMarket(), moneyMarketDiamond);
  }

  function testRevert_WhenInitializeOwnerIsNotMoneyMarket() external {
    DebtToken debtToken = deployUninitializedDebtToken();

    // expect general evm error without data since sanity check calls method that doesn't exist on ALICE
    vm.expectRevert();
    debtToken.initialize(address(weth), ALICE);
  }

  function testRevert_WhenCallInitializeAfterHasBeenInitialized() external {
    DebtToken debtToken = deployUninitializedDebtToken();

    debtToken.initialize(address(weth), moneyMarketDiamond);

    vm.expectRevert("Initializable: contract is already initialized");
    debtToken.initialize(address(weth), moneyMarketDiamond);
  }
}
