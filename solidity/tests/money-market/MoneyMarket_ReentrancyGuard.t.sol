// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseTest, console } from "../base/BaseTest.sol";
import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";

// interfaces
import { ILendFacet } from "../../contracts/money-market/interfaces/ILendFacet.sol";
import { LibReentrancyGuard } from "../../contracts/money-market/libraries/LibReentrancyGuard.sol";

contract MoneyMarket_ReentrancyGuardTest is MoneyMarket_BaseTest {
  MockAttacker attacker;

  function setUp() public override {
    super.setUp();
    attacker = new MockAttacker();
  }

  function testRevert_WhenMMGetReentrance_ShouldRevert() external {
    // wrong error message since it is expected message inside contract called.
    vm.expectRevert();
    attacker.attack{ value: 2 ether }();
  }
}

contract MockAttacker is MoneyMarket_BaseTest {
  function attack() external payable {
    accountManager.depositETH{ value: address(this).balance }();
    accountManager.withdrawETH(1 ether);
  }

  //@dev Fallback function to accept BNB.
  receive() external payable {
    vm.expectRevert(abi.encodeWithSelector(LibReentrancyGuard.LibReentrancyGuard_ReentrantCall.selector));
    accountManager.withdraw(address(ibWNative), 1 ether);
  }
}
