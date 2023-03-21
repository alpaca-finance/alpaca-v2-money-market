// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { LYF_BaseTest } from "./LYF_BaseTest.t.sol";

// libraries
import { LibDoublyLinkedList } from "../../contracts/lyf/libraries/LibDoublyLinkedList.sol";

// interfaces
import { ILYFCollateralFacet } from "../../contracts/lyf/interfaces/ILYFCollateralFacet.sol";

contract LYF_Collateral_RemoveCollateralTest is LYF_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testRevert_WhenUserRemoveLYFCollateralMoreThanExistingAmount_ShouldOnlyRemoveTheExisitingAmount() external {
    vm.startPrank(ALICE);
    weth.approve(lyfDiamond, 10 ether);
    collateralFacet.addCollateral(ALICE, 0, address(weth), 10 ether);
    vm.stopPrank();

    assertEq(weth.balanceOf(ALICE), 990 ether);
    assertEq(weth.balanceOf(lyfDiamond), 10 ether);

    vm.prank(ALICE);
    collateralFacet.removeCollateral(subAccount0, address(weth), 20 ether);

    assertEq(weth.balanceOf(ALICE), 1000 ether);
    assertEq(weth.balanceOf(lyfDiamond), 0 ether);
  }

  // todo: this test should has deebt thing to calculate borrowed used power
  // function testRevert_WhenUserRemoveLYFCollateral_BorrowingPowerLessThanUsedBorrowingPower_ShouldRevert() external {
  //   // BOB deposit 10 weth
  //   vm.startPrank(BOB);
  //   // lendFacet.deposit(address(weth), 10 ether);
  //   vm.stopPrank();

  //   // alice add collateral 10 weth
  //   vm.startPrank(ALICE);
  //   weth.approve(lyfDiamond, 10 ether);
  //   collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 10 ether);
  //   vm.stopPrank();

  //   vm.startPrank(ALICE);
  //   // alice borrow 1 weth
  //   // borrowFacet.borrow(subAccount0, address(weth), 1 ether);

  //   // alice try to remove 10 weth, this will make alice's borrowingPower < usedBorrowingPower
  //   // should revert
  //   vm.expectRevert(abi.encodeWithSelector(ILYFCollateralFacet.LYFCollateralFacet_BorrowingPowerTooLow.selector));
  //   collateralFacet.removeCollateral(subAccount0, address(weth), 10 ether);
  //   vm.stopPrank();
  // }

  function testCorrectness_WhenUserRemoveLYFCollateral_ShouldWork() external {
    uint256 _balanceBefore = weth.balanceOf(ALICE);
    uint256 _lyfBalanceBefore = weth.balanceOf(lyfDiamond);

    uint256 _addCollateralAmount = 10 ether;
    uint256 _removeCollateralAmount = _addCollateralAmount;

    // alice add collateral 10 weth
    vm.prank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), _addCollateralAmount);

    assertEq(weth.balanceOf(ALICE), _balanceBefore - _addCollateralAmount);
    assertEq(weth.balanceOf(lyfDiamond), _lyfBalanceBefore + _addCollateralAmount);
    assertEq(viewFacet.getTokenCollatAmount(address(weth)), _addCollateralAmount);

    vm.prank(ALICE);
    collateralFacet.removeCollateral(subAccount0, address(weth), _removeCollateralAmount);

    // todo: addd extenal function to check borrowing power
    // uint256 _borrowingPower = borrowFacet.getTotalBorrowingPower(ALICE, subAccount0);

    assertEq(weth.balanceOf(ALICE), _balanceBefore);
    assertEq(weth.balanceOf(lyfDiamond), _lyfBalanceBefore);
    // assertEq(_borrowingPower, 0);
    assertEq(viewFacet.getTokenCollatAmount(address(weth)), 0);
  }

  function testRevert_WhenLYFRemoveCollateralLPToken() external {
    wethUsdcLPToken.mint(ALICE, 10 ether);
    vm.startPrank(ALICE);
    wethUsdcLPToken.approve(lyfDiamond, 10 ether);
    vm.expectRevert(ILYFCollateralFacet.LYFCollateralFacet_RemoveLPCollateralNotAllowed.selector);
    collateralFacet.removeCollateral(subAccount0, address(wethUsdcLPToken), 10 ether);
  }
}
