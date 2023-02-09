// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20 } from "./MoneyMarket_BaseTest.t.sol";

// libraries
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { ICollateralFacet, LibDoublyLinkedList } from "../../contracts/money-market/facets/CollateralFacet.sol";
import { IMiniFL } from "../../contracts/money-market/interfaces/IMiniFL.sol";

contract MoneyMarket_Collateral_RemoveCollateralTest is MoneyMarket_BaseTest {
  IMiniFL _miniFL;

  function setUp() public override {
    super.setUp();

    _miniFL = IMiniFL(address(miniFL));
  }

  function _addCollatViaIbToken() internal {
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
    assertEq(viewFacet.getTotalCollat(address(weth)), _addCollateralAmount);

    vm.prank(ALICE);
    collateralFacet.removeCollateral(subAccount0, address(weth), _removeCollateralAmount);

    uint256 _borrowingPower = viewFacet.getTotalBorrowingPower(ALICE, subAccount0);

    assertEq(weth.balanceOf(ALICE), _balanceBefore);
    assertEq(weth.balanceOf(moneyMarketDiamond), _MMbalanceBefore);
    assertEq(_borrowingPower, 0);
    assertEq(viewFacet.getTotalCollat(address(weth)), 0);
  }

  // Add and Remove Collat with ibToken
  function testCorrectness_WhenRemoveCollateralViaIbToken_ibTokenCollatShouldBeCorrect() external {
    address _subAccount = viewFacet.getSubAccount(ALICE, subAccount0);
    uint256 _poolId = viewFacet.getMiniFLPoolIdFromToken(address(ibWeth));

    _addCollatViaIbToken();

    // ibToken should be staked to MiniFL when add collat by ibToken
    assertEq(ibWeth.balanceOf(ALICE), 0 ether);
    assertEq(_miniFL.getUserTotalAmountOf(_poolId, _subAccount), 10 ether);

    // check account ib token collat
    assertEq(viewFacet.getCollatAmountOf(ALICE, subAccount0, address(ibWeth)), 10 ether);

    vm.startPrank(ALICE);
    collateralFacet.removeCollateral(0, address(ibWeth), 10 ether);
    vm.stopPrank();

    // check account ib token collat
    // ibToken should be withdraw from MiniFL when remove collat
    assertEq(viewFacet.getCollatAmountOf(ALICE, subAccount0, address(ibWeth)), 0 ether);
    assertEq(_miniFL.getUserTotalAmountOf(_poolId, _subAccount), 0 ether);
    assertEq(ibWeth.balanceOf(ALICE), 10 ether);
  }

  function testCorrectness_WhenPartiallyRemoveCollateralViaIbToken_ibTokenCollatShouldBeRemain() external {
    address _subAccount = viewFacet.getSubAccount(ALICE, subAccount0);
    uint256 _poolId = viewFacet.getMiniFLPoolIdFromToken(address(ibWeth));

    _addCollatViaIbToken();

    // ibToken should be staked to MiniFL when add collat by ibToken
    uint256 _stakingAmountBefore = _miniFL.getUserTotalAmountOf(_poolId, _subAccount);
    uint256 _collatAmountBefore = viewFacet.getCollatAmountOf(ALICE, subAccount0, address(ibWeth));

    assertEq(ibWeth.balanceOf(ALICE), 0 ether);
    assertEq(_stakingAmountBefore, 10 ether);

    // check account ib token collat
    assertEq(_collatAmountBefore, 10 ether);

    vm.startPrank(ALICE);
    collateralFacet.removeCollateral(0, address(ibWeth), 5 ether);
    vm.stopPrank();

    uint256 _stakingAmountAfter = _miniFL.getUserTotalAmountOf(_poolId, _subAccount);
    uint256 _collatAmountAfter = viewFacet.getCollatAmountOf(ALICE, subAccount0, address(ibWeth));

    // check account ib token collat
    // ibToken should be withdraw from MiniFL when remove collat
    assertEq(
      viewFacet.getCollatAmountOf(ALICE, subAccount0, address(ibWeth)),
      _collatAmountBefore - _collatAmountAfter
    );
    assertEq(_miniFL.getUserTotalAmountOf(_poolId, _subAccount), _stakingAmountBefore - _stakingAmountAfter);
    assertEq(ibWeth.balanceOf(ALICE), _stakingAmountBefore - _stakingAmountAfter);
  }
}
