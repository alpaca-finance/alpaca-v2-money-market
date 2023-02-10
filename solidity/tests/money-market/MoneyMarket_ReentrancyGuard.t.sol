// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BaseTest, console } from "../base/BaseTest.sol";
import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";

// core
import { MoneyMarketDiamond } from "../../contracts/money-market/MoneyMarketDiamond.sol";

// interfaces
import { ILendFacet } from "../../contracts/money-market/facets/LendFacet.sol";
import { LibReentrancyGuard } from "../../contracts/money-market/libraries/LibReentrancyGuard.sol";

contract MoneyMarket_ReentrancyGuardTest is MoneyMarket_BaseTest {
  MockAttacker attacker;

  function setUp() public override {
    super.setUp();
    attacker = new MockAttacker(moneyMarketDiamond, address(ibWNative));
  }

  function testRevert_WhenMMGetReentrance_ShouldRevert() external {
    // wrong error message since it is expected message inside contract called.
    vm.expectRevert();
    attacker.attack(2 ether);
  }
}

contract MockAttacker is BaseTest {
  address public moneyMarket;
  address public ibWNativeToken;

  constructor(address _moneyMarket, address _ibWNativeToken) {
    moneyMarket = _moneyMarket;
    ibWNativeToken = _ibWNativeToken;
  }

  function attack(uint256 _amount) external payable {
    ILendFacet(moneyMarket).deposit(ALICE, address(weth), _amount);
    ILendFacet(moneyMarket).withdraw(ALICE, address(ibWeth), 1 ether);
  }

  //@dev Fallback function to accept BNB.
  receive() external payable {
    vm.expectRevert(abi.encodeWithSelector(LibReentrancyGuard.LibReentrancyGuard_ReentrantCall.selector));
    ILendFacet(moneyMarket).withdraw(ALICE, ibWNativeToken, 1 ether);
  }
}
