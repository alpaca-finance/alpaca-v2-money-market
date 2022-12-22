// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20 } from "./MoneyMarket_BaseTest.t.sol";

// libraries
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { ICollateralFacet, LibDoublyLinkedList } from "../../contracts/money-market/facets/CollateralFacet.sol";

contract MoneyMarket_CollateralFacetTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenAddCollateral_TokenShouldTransferFromUserToMM() external {
    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, 10 ether);
    collateralFacet.addCollateral(ALICE, 0, address(weth), 10 ether);
    vm.stopPrank();

    assertEq(weth.balanceOf(ALICE), 990 ether);
    assertEq(weth.balanceOf(moneyMarketDiamond), 10 ether);
  }

  function testCorrectness_WhenUserAddMultipleCollaterals_ListShouldUpdate() external {
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

  function testCorrectness_WhenUserAddMultipleCollaterals_TotalBorrowingPowerShouldBeCorrect() external {
    uint256 _aliceCollateralAmount = 10 ether;
    uint256 _aliceCollateralAmount2 = 20 ether;

    vm.startPrank(ALICE);

    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), _aliceCollateralAmount);

    collateralFacet.addCollateral(ALICE, subAccount0, address(usdc), _aliceCollateralAmount2);
    vm.stopPrank();

    uint256 _aliceBorrowingPower = viewFacet.getTotalBorrowingPower(ALICE, subAccount0);
    assertEq(_aliceBorrowingPower, 27 ether);
  }

  function testRevert_WhenUserAddInvalidCollateral_ShouldRevert() external {
    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(LibMoneyMarket01.LibMoneyMarket01_InvalidAssetTier.selector));
    collateralFacet.addCollateral(ALICE, subAccount0, address(isolateToken), 1 ether);
    vm.stopPrank();
  }

  function testRevert_WhenUserAddCollateralMoreThanLimit_ShouldRevert() external {
    //max collat for weth is 100 ether
    uint256 _collateral = 100 ether;
    vm.startPrank(ALICE);

    lendFacet.deposit(address(weth), 10 ether);
    // add ibWethToken
    ibWeth.approve(moneyMarketDiamond, 10 ether);
    collateralFacet.addCollateral(ALICE, 0, address(ibWeth), 10 ether);

    // first time should pass
    collateralFacet.addCollateral(ALICE, 0, address(weth), _collateral);

    // the second should revert as it will exceed the limit
    vm.expectRevert(abi.encodeWithSelector(LibMoneyMarket01.LibMoneyMarket01_ExceedCollateralLimit.selector));
    collateralFacet.addCollateral(ALICE, 0, address(weth), _collateral);

    vm.stopPrank();
  }

  function testRevert_WhenUserRemoveCollateralMoreThanExistingAmount_ShouldRevert() external {
    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, 10 ether);
    collateralFacet.addCollateral(ALICE, 0, address(weth), 10 ether);
    vm.stopPrank();

    assertEq(weth.balanceOf(ALICE), 990 ether);
    assertEq(weth.balanceOf(moneyMarketDiamond), 10 ether);

    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(LibMoneyMarket01.LibMoneyMarket01_TooManyCollateralRemoved.selector));
    collateralFacet.removeCollateral(subAccount0, address(weth), 10 ether + 1);
  }

  function testRevert_WhenUserRemoveCollateral_BorrowingPowerLessThanUsedBorrowingPower_ShouldRevert() external {
    // BOB deposit 10 weth
    vm.startPrank(BOB);
    lendFacet.deposit(address(weth), 10 ether);
    vm.stopPrank();

    // alice add collateral 10 weth
    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, 10 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 10 ether);
    vm.stopPrank();

    vm.startPrank(ALICE);
    // alice borrow 1 weth
    borrowFacet.borrow(subAccount0, address(weth), 1 ether);

    // alice try to remove 10 weth, this will make alice's borrowingPower < usedBorrowingPower
    // should revert
    vm.expectRevert(abi.encodeWithSelector(LibMoneyMarket01.LibMoneyMarket01_BorrowingPowerTooLow.selector));
    collateralFacet.removeCollateral(subAccount0, address(weth), 10 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserRemoveCollateral_ShouldWork() external {
    uint256 _balanceBefore = weth.balanceOf(ALICE);
    uint256 _MMbalanceBefore = weth.balanceOf(moneyMarketDiamond);

    uint256 _addCollateralAmount = 10 ether;
    uint256 _removeCollateralAmount = _addCollateralAmount;

    // alice add collateral 10 weth
    vm.prank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), _addCollateralAmount);

    assertEq(weth.balanceOf(ALICE), _balanceBefore - _addCollateralAmount);
    assertEq(weth.balanceOf(moneyMarketDiamond), _MMbalanceBefore + _addCollateralAmount);
    assertEq(viewFacet.getTotalCollatOfToken(address(weth)), _addCollateralAmount);

    vm.prank(ALICE);
    collateralFacet.removeCollateral(subAccount0, address(weth), _removeCollateralAmount);

    uint256 _borrowingPower = viewFacet.getTotalBorrowingPower(ALICE, subAccount0);

    assertEq(weth.balanceOf(ALICE), _balanceBefore);
    assertEq(weth.balanceOf(moneyMarketDiamond), _MMbalanceBefore);
    assertEq(_borrowingPower, 0);
    assertEq(viewFacet.getTotalCollatOfToken(address(weth)), 0);
  }

  function testCorrectness_WhenUserTransferCollateralBTWSubAccount_ShouldWork() external {
    uint256 _addCollateralAmount = 10 ether;
    uint256 _transferCollateralAmount = 1 ether;

    // alice add collateral 10 weth
    vm.prank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), _addCollateralAmount);

    uint256 _MMbalanceBeforeTransfer = weth.balanceOf(moneyMarketDiamond);
    uint256 _balanceBeforeTransfer = weth.balanceOf(ALICE);
    uint256 _wethCollateralAmountBeforeTransfer = viewFacet.getTotalCollatOfToken(address(weth));

    // alice transfer collateral from subAccount0 to subAccount1
    vm.prank(ALICE);
    collateralFacet.transferCollateral(subAccount0, subAccount1, address(weth), _transferCollateralAmount);

    LibDoublyLinkedList.Node[] memory subAccount0CollatList = viewFacet.getAllSubAccountCollats(ALICE, subAccount0);

    LibDoublyLinkedList.Node[] memory subAccount1CollatList = viewFacet.getAllSubAccountCollats(ALICE, subAccount1);

    uint256 _subAccount0BorrowingPower = viewFacet.getTotalBorrowingPower(ALICE, subAccount0);

    uint256 _subAccount1BorrowingPower = viewFacet.getTotalBorrowingPower(ALICE, subAccount1);

    // validate
    // subAccount0
    assertEq(subAccount0CollatList[0].amount, 9 ether);
    // 9 ether * 9000/ 10000
    assertEq(_subAccount0BorrowingPower, 8.1 ether);
    // subAccount1
    assertEq(subAccount1CollatList[0].amount, _transferCollateralAmount);
    // 1 ether * 9000/ 10000
    assertEq(_subAccount1BorrowingPower, 0.9 ether);

    // Global states
    assertEq(weth.balanceOf(moneyMarketDiamond), _MMbalanceBeforeTransfer);
    assertEq(viewFacet.getTotalCollatOfToken(address(weth)), _wethCollateralAmountBeforeTransfer);
    assertEq(weth.balanceOf(ALICE), _balanceBeforeTransfer);
  }

  // Add Collat with ibToken
  function testCorrectness_WhenAddCollateralViaIbToken_ibTokenShouldTransferFromUserToMM() external {
    // LEND to get ibToken
    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, 10 ether);
    lendFacet.deposit(address(weth), 10 ether);
    vm.stopPrank();

    vm.warp(block.timestamp + 100);
    // Add collat by ibToken
    vm.startPrank(ALICE);
    ibWeth.approve(moneyMarketDiamond, 10 ether);
    collateralFacet.addCollateral(ALICE, 0, address(ibWeth), 10 ether);
    vm.stopPrank();

    assertEq(weth.balanceOf(ALICE), 990 ether);
    assertEq(ibWeth.balanceOf(ALICE), 0 ether);

    assertEq(weth.balanceOf(moneyMarketDiamond), 10 ether);
    assertEq(ibWeth.balanceOf(moneyMarketDiamond), 10 ether);

    // check account ib token collat
    address _aliceSubaccount0 = address(uint160(ALICE) ^ uint160(0));
    assertEq(viewFacet.getOverCollatSubAccountCollatAmount(_aliceSubaccount0, address(ibWeth)), 10 ether);
  }

  // Add and Remove Collat with ibToken
  function testCorrectness_WhenRemoveCollateralViaIbToken_ibTokenCollatShouldBeCorrect() external {
    // LEND to get ibToken
    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, 10 ether);
    lendFacet.deposit(address(weth), 10 ether);
    vm.stopPrank();

    // Add collat by ibToken
    vm.startPrank(ALICE);
    ibWeth.approve(moneyMarketDiamond, 10 ether);
    collateralFacet.addCollateral(ALICE, 0, address(ibWeth), 10 ether);
    vm.stopPrank();

    // check account ib token collat
    address _aliceSubaccount0 = address(uint160(ALICE) ^ uint160(0));
    assertEq(viewFacet.getOverCollatSubAccountCollatAmount(_aliceSubaccount0, address(ibWeth)), 10 ether);

    vm.startPrank(ALICE);
    collateralFacet.removeCollateral(0, address(ibWeth), 10 ether);
    vm.stopPrank();

    // check account ib token collat

    assertEq(viewFacet.getOverCollatSubAccountCollatAmount(_aliceSubaccount0, address(ibWeth)), 0 ether);
  }
}
