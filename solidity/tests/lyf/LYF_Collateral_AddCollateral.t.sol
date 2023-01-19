// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, console } from "./LYF_BaseTest.t.sol";

// libraries
import { LibDoublyLinkedList } from "../../contracts/lyf/libraries/LibDoublyLinkedList.sol";
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";

// interfaces
import { ILYFCollateralFacet } from "../../contracts/lyf/interfaces/ILYFCollateralFacet.sol";

// mocks
import { MockERC20 } from "../mocks/MockERC20.sol";

contract LYF_Collateral_AddCollateralTest is LYF_BaseTest {
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

  function testRevert_WhenLYFAddCollateralWithLPToken() external {
    wethUsdcLPToken.mint(ALICE, 10 ether);
    vm.startPrank(ALICE);
    wethUsdcLPToken.approve(lyfDiamond, 10 ether);
    vm.expectRevert(
      abi.encodeWithSelector(
        ILYFCollateralFacet.LYFCollateralFacet_TokenNotAllowedAsCollateral.selector,
        address(wethUsdcLPToken)
      )
    );
    collateralFacet.addCollateral(ALICE, subAccount0, address(wethUsdcLPToken), 10 ether);
  }

  function testRevert_WhenLYFAddCollateralWithUnlisedToken() external {
    MockERC20 _unlistedToken = new MockERC20("UNLISTED", "UNLISTED", 18);
    _unlistedToken.mint(ALICE, 10 ether);
    vm.startPrank(ALICE);
    _unlistedToken.approve(lyfDiamond, 10 ether);
    vm.expectRevert(
      abi.encodeWithSelector(
        ILYFCollateralFacet.LYFCollateralFacet_TokenNotAllowedAsCollateral.selector,
        address(_unlistedToken)
      )
    );
    collateralFacet.addCollateral(ALICE, subAccount0, address(_unlistedToken), 10 ether);
  }

  function testCorrectness_WhenLYFAddCollateralZeroAmount_ShouldNotAddNewNode() external {
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 0);
    LibDoublyLinkedList.Node[] memory _subAccountCollats = viewFacet.getAllSubAccountCollats(ALICE, subAccount0);
    assertEq(_subAccountCollats.length, 0);
  }
}
