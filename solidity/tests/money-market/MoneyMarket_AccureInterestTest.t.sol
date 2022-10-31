// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, console } from "./MoneyMarket_BaseTest.t.sol";

// interfaces
import { IBorrowFacet, LibDoublyLinkedList } from "../../contracts/money-market/facets/BorrowFacet.sol";
import { IAdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";
import { FixedInterestRateModel, IInterestRateModel } from "../../contracts/money-market/interest-model/FixedInterestRateModel.sol";

contract MoneyMarket_AccureInterestTest is MoneyMarket_BaseTest {
  MockERC20 mockToken;

  function setUp() public override {
    super.setUp();

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    FixedInterestRateModel model = new FixedInterestRateModel();
    adminFacet.setInterestModels(address(weth), address(model));
    adminFacet.setInterestModels(address(usdc), address(model));
    adminFacet.setInterestModels(address(isolateToken), address(model));

    vm.startPrank(ALICE);
    lendFacet.deposit(address(weth), 50 ether);
    lendFacet.deposit(address(usdc), 20 ether);
    lendFacet.deposit(address(isolateToken), 20 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserBorrowTokenFromMM_ShouldBeCorrectPendingInterest()
    external
  {
    uint256 _actualInterest = borrowFacet.pendingInterest(address(weth));
    assertEq(_actualInterest, 0);

    uint256 _borrowAmount = 10 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(
      BOB,
      subAccount0,
      address(weth),
      _borrowAmount * 2
    );

    uint256 _bobBalanceBefore = weth.balanceOf(BOB);
    borrowFacet.borrow(subAccount0, address(weth), _borrowAmount);
    vm.stopPrank();

    uint256 _bobBalanceAfter = weth.balanceOf(BOB);

    assertEq(_bobBalanceAfter - _bobBalanceBefore, _borrowAmount);

    uint256 _debtAmount;
    (, _debtAmount) = borrowFacet.getDebt(BOB, subAccount0, address(weth));
    assertEq(_debtAmount, _borrowAmount);

    vm.warp(block.timestamp + 10);
    uint256 _expectedDebtAmount = 10e18 + _borrowAmount;

    uint256 _actualInterestAfter = borrowFacet.pendingInterest(address(weth));
    assertEq(_actualInterestAfter, 10e18);
    borrowFacet.accureInterest(address(weth));
    (, uint256 _actualDebtAmount) = borrowFacet.getDebt(
      BOB,
      subAccount0,
      address(weth)
    );
    assertEq(_actualDebtAmount, _expectedDebtAmount);

    // FIXME last accuretime
    uint256 _actualAccureTime = borrowFacet.debtLastAccureTime(address(weth));

    assertEq(_actualAccureTime, 11);
  }

  function testCorrectness_WhenAddCollateralAndUserBorrow_ShouldNotGetInterest()
    external
  {
    uint256 _balanceAliceBefore = weth.balanceOf(ALICE);
    uint256 _balanceMMDiamondBefore = weth.balanceOf(moneyMarketDiamond);
    uint256 _aliceCollateralAmount = 10 ether;

    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, _aliceCollateralAmount);
    collateralFacet.addCollateral(
      ALICE,
      0,
      address(weth),
      _aliceCollateralAmount
    );
    vm.stopPrank();

    assertEq(
      weth.balanceOf(ALICE),
      _balanceAliceBefore - _aliceCollateralAmount
    );
    assertEq(
      weth.balanceOf(moneyMarketDiamond),
      _balanceMMDiamondBefore + _aliceCollateralAmount
    );

    vm.warp(block.timestamp + 10);

    //when someone borrow
    uint256 _bobBorrowAmount = 10 ether;
    vm.startPrank(BOB);
    collateralFacet.addCollateral(
      BOB,
      subAccount0,
      address(weth),
      _bobBorrowAmount * 2
    );

    uint256 _bobBalanceBeforeBorrow = weth.balanceOf(BOB);
    borrowFacet.borrow(subAccount0, address(weth), _bobBorrowAmount);

    (, uint256 _actualBobDebtAmountBeforeWarp) = borrowFacet.getDebt(
      BOB,
      subAccount0,
      address(weth)
    );
    assertEq(_actualBobDebtAmountBeforeWarp, _bobBorrowAmount);
    vm.stopPrank();

    uint256 _bobBalanceAfterBorrow = weth.balanceOf(BOB);

    assertEq(
      _bobBalanceAfterBorrow - _bobBalanceBeforeBorrow,
      _bobBorrowAmount
    );
    vm.warp(block.timestamp + 10);
    borrowFacet.accureInterest(address(weth));
    (, uint256 _actualBobDebtAmountAfter) = borrowFacet.getDebt(
      BOB,
      subAccount0,
      address(weth)
    );

    assertEq(
      _actualBobDebtAmountAfter - _actualBobDebtAmountBeforeWarp,
      10 ether
    );

    uint256 wethAliceBeforeWithdraw = weth.balanceOf(ALICE);
    vm.prank(ALICE);
    collateralFacet.removeCollateral(0, address(weth), 10 ether);
    uint256 wethAliceAfterWithdraw = weth.balanceOf(ALICE);
    assertEq(wethAliceAfterWithdraw - wethAliceBeforeWithdraw, 10 ether);
    LibDoublyLinkedList.Node[] memory collats = collateralFacet.getCollaterals(
      ALICE,
      0
    );
    assertEq(collats.length, 0);
  }

  /* 2 borrower 1 depositors
    alice deposit
    bob borrow

  */

  /*  1 borrower 2 depositors
   */

  // TODO
  function testCorrectness_MultipleAction_ShouldGetInterestAndActionCorrectly()
    external
  {
    /* 2 borrower 2 depositors
      1.alice deposit
      2.bob borrowed
      3.10sec passed cat deposit
      4.10sec eve borrowed
      5.after accure debt
      
      6.verify is it not be able more 
      verify eve interest < bob  (borrow the same amount)
      verify cat interest < alice (deposit same amount)
    */
  }
}
