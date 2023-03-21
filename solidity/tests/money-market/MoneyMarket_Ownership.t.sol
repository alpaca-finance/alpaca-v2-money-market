// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest, console } from "./MoneyMarket_BaseTest.t.sol";

import { IMMOwnershipFacet } from "../../contracts/money-market/interfaces/IMMOwnershipFacet.sol";

contract MoneyMarket_OwnershipTest is MoneyMarket_BaseTest {
  event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenTransferOwnership_ShouldSetPendingOwner() external {
    assertEq(MMOwnershipFacet.owner(), address(this));
    assertEq(MMOwnershipFacet.pendingOwner(), address(0));

    vm.expectEmit(true, true, false, false, moneyMarketDiamond);
    emit OwnershipTransferStarted(address(this), ALICE);

    MMOwnershipFacet.transferOwnership(ALICE);

    assertEq(MMOwnershipFacet.owner(), address(this));
    assertEq(MMOwnershipFacet.pendingOwner(), ALICE);
  }

  function testCorrectness_WhenAcceptOwnership_ShouldSetNewOwner() external {
    MMOwnershipFacet.transferOwnership(ALICE);

    vm.expectEmit(true, true, false, false, moneyMarketDiamond);
    emit OwnershipTransferred(address(this), ALICE);
    vm.prank(ALICE);
    MMOwnershipFacet.acceptOwnership();

    assertEq(MMOwnershipFacet.owner(), ALICE);
    assertEq(MMOwnershipFacet.pendingOwner(), address(0));
  }

  function testRevert_WhenTransferOwnership_CallerIsNotPendingOwner() external {
    MMOwnershipFacet.transferOwnership(ALICE);

    vm.expectRevert(IMMOwnershipFacet.MMOwnershipFacet_CallerIsNotPendingOwner.selector);
    vm.prank(BOB);
    MMOwnershipFacet.acceptOwnership();
  }

  function testRevert_WhenTransferOwnership_CallerIsNotOwner() external {
    vm.expectRevert("LibDiamond: Must be contract owner");

    vm.prank(ALICE);
    MMOwnershipFacet.transferOwnership(ALICE);
  }
}
