// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20 } from "./MoneyMarket_BaseTest.t.sol";

// interfaces
import { ICollateralFacet, LibCollateraleralDoublyLinkedList } from "../../contracts/money-market/facets/CollateralFacet.sol";

contract MoneyMarket_CollateralFacetTest is MoneyMarket_BaseTest {
  uint256 subAccount0 = 0;
  MockERC20 mockToken;

  function setUp() public override {
    super.setUp();

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    mockToken.approve(moneyMarketDiamond, type(uint256).max);
    vm.stopPrank();
  }

  function testCorrectness_WhenAddCollateral_TokenShouldTransferFromUserToMM()
    external
  {
    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, 10 ether);
    collateralFacet.addCollateral(ALICE, 0, address(weth), 10 ether);
    vm.stopPrank();

    assertEq(weth.balanceOf(ALICE), 990 ether);
    assertEq(weth.balanceOf(moneyMarketDiamond), 10 ether);
  }

  function testCorrectness_WhenUserAddMultipleCollaterals_ListShouldUpdate()
    external
  {
    uint256 _aliceCollateralAmount = 10 ether;
    uint256 _aliceCollateralAmount2 = 20 ether;

    vm.startPrank(ALICE);

    collateralFacet.addCollateral(
      ALICE,
      subAccount0,
      address(weth),
      _aliceCollateralAmount
    );
    vm.stopPrank();

    LibCollateraleralDoublyLinkedList.Collateral[]
      memory collats = collateralFacet.getCollaterals(ALICE, subAccount0);

    assertEq(collats.length, 1);
    assertEq(collats[0].amount, _aliceCollateralAmount);

    vm.startPrank(ALICE);

    // list will be add at the front of linkList
    collateralFacet.addCollateral(
      ALICE,
      subAccount0,
      address(mockToken),
      _aliceCollateralAmount2
    );
    vm.stopPrank();

    collats = collateralFacet.getCollaterals(ALICE, subAccount0);

    assertEq(collats.length, 2);
    assertEq(collats[0].amount, _aliceCollateralAmount2);
    assertEq(collats[1].amount, _aliceCollateralAmount);

    // Alice try to update weth collateral
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(
      ALICE,
      subAccount0,
      address(weth),
      _aliceCollateralAmount
    );
    vm.stopPrank();

    collats = collateralFacet.getCollaterals(ALICE, subAccount0);

    assertEq(collats.length, 2);
    assertEq(collats[0].amount, _aliceCollateralAmount2);
    assertEq(collats[1].amount, _aliceCollateralAmount * 2, "updated weth");
  }
}
