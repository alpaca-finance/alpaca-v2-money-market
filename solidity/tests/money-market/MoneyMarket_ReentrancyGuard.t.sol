// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BaseTest, console } from "../base/BaseTest.sol";
import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";

// core
import { MoneyMarketDiamond } from "../../contracts/money-market/MoneyMarketDiamond.sol";

// interfaces
import { ILendFacet } from "../../contracts/money-market/facets/LendFacet.sol";
import { LibReentrancyGuard } from "../../contracts/money-market/libraries/LibReentrancyGuard.sol";

contract MoneyMarket_LendFacetTest is MoneyMarket_BaseTest {
  MockAttacker attacker;

  function setUp() public override {
    super.setUp();
    attacker = new MockAttacker(moneyMarketDiamond, address(ibWNative));
  }

  function testRevert_WhenMMGetReentrance_ShouldRevert() external {
    // wrong error massge since it is expected message inside contract called.
    vm.expectRevert();
    attacker.attack{ value: 2 ether }();
  }
}

contract MockAttacker is BaseTest {
  address public moneyMarket;
  address public ibWNativeToken;

  constructor(address _moneyMarket, address _ibWNativeToken) {
    moneyMarket = _moneyMarket;
    ibWNativeToken = _ibWNativeToken;
  }

  function attack() external payable {
    ILendFacet(moneyMarket).depositETH{ value: address(this).balance }();
    ILendFacet(moneyMarket).withdrawETH(ibWNativeToken, 1 ether);
  }

  //@dev Fallback function to accept BNB.
  receive() external payable {
    vm.expectRevert(abi.encodeWithSelector(LibReentrancyGuard.LibReentrancyGuard_ReentrantCall.selector));
    ILendFacet(moneyMarket).withdraw(ibWNativeToken, 1 ether);
  }
}
