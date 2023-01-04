// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest } from "./LYF_BaseTest.t.sol";

// libraries
import { LibDoublyLinkedList } from "../../contracts/lyf/libraries/LibDoublyLinkedList.sol";
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";

// interfaces
import { ILYFCollateralFacet } from "../../contracts/lyf/interfaces/ILYFCollateralFacet.sol";

contract LYF_CollateralFacetTest is LYF_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenAddLYFCollateral_TokenShouldTransferFromUserToMM() external {
    vm.startPrank(ALICE);
    uint256 _aliceBalanceBefore = weth.balanceOf(ALICE);
    weth.approve(lyfDiamond, 10 ether);
    collateralFacet.addCollateral(ALICE, 0, address(weth), 10 ether);
    vm.stopPrank();
    uint256 _aliceBalanceAfter = weth.balanceOf(ALICE);

    assertEq(_aliceBalanceBefore - _aliceBalanceAfter, 10 ether);
    assertEq(weth.balanceOf(lyfDiamond), 10 ether);
  }

  function testRevert_WhenAddLYFCollateralTooMuchToken() external {
    vm.startPrank(ALICE);
    weth.approve(lyfDiamond, 10 ether);
    collateralFacet.addCollateral(ALICE, 0, address(weth), 10 ether);
    usdc.approve(lyfDiamond, 10 ether);
    collateralFacet.addCollateral(ALICE, 0, address(usdc), 10 ether);
    btc.approve(lyfDiamond, 10 ether);
    collateralFacet.addCollateral(ALICE, 0, address(btc), 10 ether);

    // now maximum is 3 token per account, when try add collat 4th token should revert
    cake.approve(lyfDiamond, 10 ether);
    vm.expectRevert(abi.encodeWithSelector(LibLYF01.LibLYF01_NumberOfTokenExceedLimit.selector));
    collateralFacet.addCollateral(ALICE, 0, address(cake), 10 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserAddMultipleLYFCollaterals_ListShouldUpdate() external {
    uint256 _aliceCollateralAmount = 10 ether;
    uint256 _aliceCollateralAmount2 = 20 ether;

    vm.startPrank(ALICE);

    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), _aliceCollateralAmount);
    vm.stopPrank();

    LibDoublyLinkedList.Node[] memory collats = viewFacet.getAllSubAccountCollats(ALICE, subAccount0);

    assertEq(collats.length, 1);
    assertEq(collats[0].amount, _aliceCollateralAmount);

    vm.startPrank(ALICE);

    // list will be add at the front of linkList
    collateralFacet.addCollateral(ALICE, subAccount0, address(usdc), _aliceCollateralAmount2);
    vm.stopPrank();

    collats = viewFacet.getAllSubAccountCollats(ALICE, subAccount0);

    assertEq(collats.length, 2);
    assertEq(collats[0].amount, _aliceCollateralAmount2);
    assertEq(collats[1].amount, _aliceCollateralAmount);

    // Alice try to update weth collateral
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), _aliceCollateralAmount);
    vm.stopPrank();

    collats = viewFacet.getAllSubAccountCollats(ALICE, subAccount0);

    assertEq(collats.length, 2);
    assertEq(collats[0].amount, _aliceCollateralAmount2);
    assertEq(collats[1].amount, _aliceCollateralAmount * 2, "updated weth");
  }

  function testCorrectness_WhenUserAddMultipleLYFCollaterals_TotalBorrowingPowerShouldBeCorrect() external {
    uint256 _aliceCollateralAmount = 10 ether;
    uint256 _aliceCollateralAmount2 = 20 ether;

    vm.startPrank(ALICE);

    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), _aliceCollateralAmount);

    collateralFacet.addCollateral(ALICE, subAccount0, address(usdc), _aliceCollateralAmount2);
    vm.stopPrank();

    // uint256 _aliceBorrowingPower = borrowFacet.getTotalBorrowingPower(ALICE, subAccount0);
    // assertEq(_aliceBorrowingPower, 27 ether);
  }

  function testRevert_WhenUserAddLYFCollateralMoreThanLimit_ShouldRevert() external {
    //max collat for weth is 100 ether
    uint256 _collateral = 100 ether;

    // mint ibToken to ALICE
    vm.prank(moneyMarketDiamond);
    ibWeth.onDeposit(ALICE, 0, 10 ether);

    vm.startPrank(ALICE);

    ibWeth.approve(lyfDiamond, 10 ether);
    collateralFacet.addCollateral(ALICE, 0, address(ibWeth), 10 ether);

    // first time should pass
    collateralFacet.addCollateral(ALICE, 0, address(weth), _collateral);

    // the second should revert as it will exceed the limit
    vm.expectRevert(abi.encodeWithSelector(ILYFCollateralFacet.LYFCollateralFacet_ExceedCollateralLimit.selector));
    collateralFacet.addCollateral(ALICE, 0, address(weth), _collateral);

    vm.stopPrank();
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

  // Add Collat with ibToken
  function testCorrectness_WhenAddLYFCollateralViaIbToken_ibTokenShouldTransferFromUserToLYF() external {
    // mint ibToken to ALICE
    vm.prank(moneyMarketDiamond);
    ibWeth.onDeposit(ALICE, 0, 10 ether);
    assertEq(ibWeth.balanceOf(ALICE), 10 ether);

    // Add collat by ibToken
    vm.startPrank(ALICE);
    ibWeth.approve(lyfDiamond, 10 ether);
    collateralFacet.addCollateral(ALICE, 0, address(ibWeth), 10 ether);
    vm.stopPrank();

    assertEq(ibWeth.balanceOf(ALICE), 0 ether);
    assertEq(ibWeth.balanceOf(lyfDiamond), 10 ether);
  }
}
