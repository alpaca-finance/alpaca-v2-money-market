// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, console } from "./MoneyMarket_BaseTest.t.sol";

import { IOwnershipFacet } from "../../contracts/money-market/interfaces/IOwnershipFacet.sol";

contract MoneyMarket_OwnershipTest is MoneyMarket_BaseTest {
  event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenTransferOwnership_ShouldSetPendingOwner() external {
    assertEq(ownershipFacet.owner(), address(this));
    assertEq(ownershipFacet.pendingOwner(), address(0));

    vm.expectEmit(true, true, false, false, moneyMarketDiamond);
    emit OwnershipTransferStarted(address(this), ALICE);

    ownershipFacet.transferOwnership(ALICE);

    assertEq(ownershipFacet.owner(), address(this));
    assertEq(ownershipFacet.pendingOwner(), ALICE);
  }

  function testCorrectness_WhenAcceptOwnership_ShouldSetNewOwner() external {
    ownershipFacet.transferOwnership(ALICE);

    vm.expectEmit(true, true, false, false, moneyMarketDiamond);
    emit OwnershipTransferred(address(this), ALICE);
    vm.prank(ALICE);
    ownershipFacet.acceptOwnership();

    assertEq(ownershipFacet.owner(), ALICE);
    assertEq(ownershipFacet.pendingOwner(), address(0));
  }

  function testRevert_WhenTransferOwnership_CallerIsNotPendingOwner() external {
    ownershipFacet.transferOwnership(ALICE);

    vm.expectRevert(IOwnershipFacet.OwnershipFacet_CallerIsNotPendingOwner.selector);
    vm.prank(BOB);
    ownershipFacet.acceptOwnership();
  }

  function testRevert_WhenTransferOwnership_CallerIsNotOwner() external {
    vm.expectRevert("LibDiamond: Must be contract owner");

    vm.prank(ALICE);
    ownershipFacet.transferOwnership(ALICE);
  }
}
