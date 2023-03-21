// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { LYF_BaseTest, console } from "./LYF_BaseTest.t.sol";

import { ILYFOwnershipFacet } from "../../contracts/lyf/interfaces/ILYFOwnershipFacet.sol";

contract LYF_OwnershipFacetTest is LYF_BaseTest {
  event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenLYFTransferOwnership_ShouldSetPendingOwner() external {
    assertEq(ownershipFacet.owner(), address(this));
    assertEq(ownershipFacet.pendingOwner(), address(0));

    vm.expectEmit(true, true, false, false, lyfDiamond);
    emit OwnershipTransferStarted(address(this), ALICE);

    ownershipFacet.transferOwnership(ALICE);

    assertEq(ownershipFacet.owner(), address(this));
    assertEq(ownershipFacet.pendingOwner(), ALICE);
  }

  function testCorrectness_WhenAcceptOwnership_ShouldSetNewOwner() external {
    ownershipFacet.transferOwnership(ALICE);

    vm.expectEmit(true, true, false, false, lyfDiamond);
    emit OwnershipTransferred(address(this), ALICE);
    vm.prank(ALICE);
    ownershipFacet.acceptOwnership();

    assertEq(ownershipFacet.owner(), ALICE);
    assertEq(ownershipFacet.pendingOwner(), address(0));
  }

  function testRevert_WhenTransferOwnership_CallerIsNotPendingOwner() external {
    ownershipFacet.transferOwnership(ALICE);

    vm.expectRevert(ILYFOwnershipFacet.LYFOwnershipFacet_CallerIsNotPendingOwner.selector);
    vm.prank(BOB);
    ownershipFacet.acceptOwnership();
  }

  function testRevert_WhenTransferOwnership_CallerIsNotOwner() external {
    vm.expectRevert("LibDiamond: Must be contract owner");

    vm.prank(ALICE);
    ownershipFacet.transferOwnership(ALICE);
  }
}
