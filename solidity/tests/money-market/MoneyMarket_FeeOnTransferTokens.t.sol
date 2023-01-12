// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// mocks
import { MockFeeOnTransferToken } from "../mocks/MockFeeOnTransferToken.sol";

contract MoneyMarket_FeeOnTransferTokensTest is MoneyMarket_BaseTest {
  MockFeeOnTransferToken internal fotToken;

  function setUp() public override {
    super.setUp();

    fotToken = new MockFeeOnTransferToken("Fee on transfer", "FOT", 18, 100);

    fotToken.mint(BOB, 100 ether);

    vm.prank(BOB);
    fotToken.approve(moneyMarketDiamond, type(uint256).max);

    adminFacet.openMarket(address(fotToken));

    mockOracle.setTokenPrice(address(fotToken), 1 ether);
  }

  function testRevert_WhenDepositWithFeeOnTransferToken() external {
    vm.prank(BOB);
    vm.expectRevert(LibMoneyMarket01.LibMoneyMarket01_FeeOnTransferTokensNotSupported.selector);
    lendFacet.deposit(address(fotToken), 1 ether);
  }

  function testRevert_WhenAddCollateralWithFeeOnTransferToken() external {
    vm.prank(BOB);
    vm.expectRevert(LibMoneyMarket01.LibMoneyMarket01_FeeOnTransferTokensNotSupported.selector);
    collateralFacet.addCollateral(BOB, subAccount0, address(fotToken), 1 ether);
  }

  // can't test repay and repurchase since we can open market but can't deposit liquidity
  // so borrowing is not possible
}
