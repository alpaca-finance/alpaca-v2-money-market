// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, console } from "../MoneyMarket_BaseTest.t.sol";

// contracts
import { InterestBearingToken } from "../../../contracts/money-market/InterestBearingToken.sol";

// interfaces
import { IAdminFacet, LibMoneyMarket01 } from "../../../contracts/money-market/facets/AdminFacet.sol";

contract InterestBearingToken_InitializerTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenInitialize_ShouldWork() external {
    InterestBearingToken ibToken = new InterestBearingToken();

    // should revert because haven't set underlying asset via initialize
    vm.expectRevert();
    ibToken.symbol();

    ibToken.initialize(address(weth), moneyMarketDiamond);

    // check properties inherited from underlying
    assertEq(ibToken.symbol(), string.concat("ib", weth.symbol()));
    assertEq(ibToken.name(), string.concat("Interest Bearing ", weth.symbol()));
    assertEq(ibToken.decimals(), weth.decimals());

    // check money market being set correctly
    assertEq(ibToken.owner(), moneyMarketDiamond);
    assertEq(ibToken.moneyMarket(), moneyMarketDiamond);
    // sanity check
    ibToken.convertToShares(1 ether);
  }

  function testRevert_WhenInitializeOwnerIsNotMoneyMarket() external {
    InterestBearingToken ibToken = new InterestBearingToken();

    // expect general evm error without data since sanity check calls method that doesn't exist on ALICE
    vm.expectRevert();
    ibToken.initialize(address(weth), ALICE);
  }

  function testRevert_WhenCallInitializeAfterHasBeenInitialized() external {
    InterestBearingToken ibToken = new InterestBearingToken();

    ibToken.initialize(address(weth), moneyMarketDiamond);

    vm.expectRevert("Initializable: contract is already initialized");
    ibToken.initialize(address(weth), moneyMarketDiamond);
  }
}
