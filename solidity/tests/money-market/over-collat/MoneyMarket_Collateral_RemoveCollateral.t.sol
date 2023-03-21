// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest, MockERC20 } from "../MoneyMarket_BaseTest.t.sol";

// libraries
import { LibMoneyMarket01 } from "../../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { ICollateralFacet } from "../../../contracts/money-market/interfaces/ICollateralFacet.sol";
import { IMiniFL } from "../../../contracts/money-market/interfaces/IMiniFL.sol";

contract MoneyMarket_Collateral_RemoveCollateralTest is MoneyMarket_BaseTest {
  IMiniFL _miniFL;

  function setUp() public override {
    super.setUp();

    _miniFL = IMiniFL(address(miniFL));
  }

  function testRevert_WhenUserRemoveCollateralMoreThanExistingAmount_ShouldRevert() external {
    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, 10 ether);
    accountManager.addCollateralFor(ALICE, 0, address(weth), 10 ether);
    vm.stopPrank();

    assertEq(weth.balanceOf(ALICE), 990 ether);
    assertEq(weth.balanceOf(moneyMarketDiamond), 10 ether);

    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(LibMoneyMarket01.LibMoneyMarket01_TooManyCollateralRemoved.selector));
    accountManager.removeCollateral(subAccount0, address(weth), 10 ether + 1);
  }

  function testRevert_WhenUserRemoveCollateral_BorrowingPowerLessThanUsedBorrowingPower_ShouldRevert() external {
    // BOB deposit 10 weth
    vm.startPrank(BOB);
    accountManager.deposit(address(weth), 10 ether);
    vm.stopPrank();

    // alice add collateral 10 weth
    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, 10 ether);
    accountManager.addCollateralFor(ALICE, subAccount0, address(weth), 10 ether);
    vm.stopPrank();

    vm.startPrank(ALICE);
    // alice borrow 1 weth
    accountManager.borrow(subAccount0, address(weth), 1 ether);

    // alice try to remove 10 weth, this will make alice's borrowingPower < usedBorrowingPower
    // should revert
    vm.expectRevert(abi.encodeWithSelector(LibMoneyMarket01.LibMoneyMarket01_BorrowingPowerTooLow.selector));
    accountManager.removeCollateral(subAccount0, address(weth), 10 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserRemoveCollateral_ShouldWork() external {
    uint256 _balanceBefore = weth.balanceOf(ALICE);
    uint256 _MMbalanceBefore = weth.balanceOf(moneyMarketDiamond);

    uint256 _addCollateralAmount = 10 ether;
    uint256 _removeCollateralAmount = _addCollateralAmount;

    // alice add collateral 10 weth
    vm.prank(ALICE);
    accountManager.addCollateralFor(ALICE, subAccount0, address(weth), _addCollateralAmount);

    assertEq(weth.balanceOf(ALICE), _balanceBefore - _addCollateralAmount);
    assertEq(weth.balanceOf(moneyMarketDiamond), _MMbalanceBefore + _addCollateralAmount);
    assertEq(viewFacet.getTotalCollat(address(weth)), _addCollateralAmount);

    vm.prank(ALICE);
    accountManager.removeCollateral(subAccount0, address(weth), _removeCollateralAmount);

    uint256 _borrowingPower = viewFacet.getTotalBorrowingPower(ALICE, subAccount0);

    assertEq(weth.balanceOf(ALICE), _balanceBefore);
    assertEq(weth.balanceOf(moneyMarketDiamond), _MMbalanceBefore);
    assertEq(_borrowingPower, 0);
    assertEq(viewFacet.getTotalCollat(address(weth)), 0);
  }

  // Add and Remove Collat with ibToken
  function testCorrectness_WhenRemoveCollateralViaIbToken_ibTokenCollatShouldBeCorrect() external {
    uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(address(ibWeth));

    vm.startPrank(ALICE);
    accountManager.depositAndAddCollateral(0, address(weth), 10 ether);
    vm.stopPrank();

    // ibToken should be staked to MiniFL when add collat with ibToken
    assertEq(ibWeth.balanceOf(ALICE), 0 ether);
    assertEq(_miniFL.getUserTotalAmountOf(_poolId, ALICE), 10 ether);

    // check account ib token collat
    assertEq(viewFacet.getCollatAmountOf(ALICE, subAccount0, address(ibWeth)), 10 ether);

    vm.startPrank(ALICE);

    accountManager.removeCollateral(0, address(ibWeth), 10 ether);
    vm.stopPrank();

    // check account ib token collat
    // ibToken should be withdrawn from MiniFL when remove collat
    assertEq(viewFacet.getCollatAmountOf(ALICE, subAccount0, address(ibWeth)), 0 ether);
    assertEq(_miniFL.getUserTotalAmountOf(_poolId, ALICE), 0 ether);
    assertEq(ibWeth.balanceOf(ALICE), 10 ether);
  }

  function testCorrectness_WhenPartiallyRemoveCollateralViaIbToken_ibTokenCollatShouldBeRemain() external {
    uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(address(ibWeth));
    uint256 _removedAmount = 5 ether;

    vm.startPrank(ALICE);
    accountManager.depositAndAddCollateral(0, address(weth), 10 ether);
    vm.stopPrank();

    // ibToken should be staked to MiniFL when add collat with ibToken
    uint256 _balanceBefore = ibWeth.balanceOf(ALICE);
    uint256 _stakingAmountBefore = _miniFL.getUserTotalAmountOf(_poolId, ALICE);
    uint256 _collatAmountBefore = viewFacet.getCollatAmountOf(ALICE, subAccount0, address(ibWeth));

    assertEq(ibWeth.balanceOf(ALICE), 0 ether);
    assertEq(_stakingAmountBefore, 10 ether);

    // check account ib token collat
    assertEq(_collatAmountBefore, 10 ether);

    vm.startPrank(ALICE);
    accountManager.removeCollateral(0, address(ibWeth), _removedAmount);
    vm.stopPrank();

    uint256 _balanceAfter = ibWeth.balanceOf(ALICE);
    uint256 _stakingAmountAfter = _miniFL.getUserTotalAmountOf(_poolId, ALICE);
    uint256 _collatAmountAfter = viewFacet.getCollatAmountOf(ALICE, subAccount0, address(ibWeth));

    // check account ib token collat
    // ibToken should be withdrawn from MiniFL when remove collat
    // collateral amount should be reduced by _removedAmount, also staking amount
    assertEq(_collatAmountBefore - _removedAmount, _collatAmountAfter);
    assertEq(_stakingAmountBefore - _removedAmount, _stakingAmountAfter);
    // after removing collateral, token should be returned to user equal to _removedAmount
    assertEq(_balanceAfter - _balanceBefore, _removedAmount);
  }
}
