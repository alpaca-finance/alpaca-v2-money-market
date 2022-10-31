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
    console.log("before use case", block.timestamp);
    uint256 _actualInterest = lendFacet.pendingInterest(address(weth));
    assertEq(_actualInterest, 0);

    uint256 _borrowAmount = 10 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(
      BOB,
      subAccount0,
      address(weth),
      _borrowAmount * 2
    );
    console.log("added Collateral", block.timestamp);

    uint256 _bobBalanceBefore = weth.balanceOf(BOB);
    borrowFacet.borrow(subAccount0, address(weth), _borrowAmount);
    vm.stopPrank();

    console.log("borrowed", block.timestamp);

    uint256 _bobBalanceAfter = weth.balanceOf(BOB);

    assertEq(_bobBalanceAfter - _bobBalanceBefore, _borrowAmount);

    uint256 _debtAmount;
    (, _debtAmount) = borrowFacet.getDebt(BOB, subAccount0, address(weth));
    assertEq(_debtAmount, _borrowAmount);

    console.log("timestamp", block.timestamp);

    vm.warp(block.timestamp + 10);
    uint256 _expectedDebtAmount = 10e18 + _borrowAmount;

    uint256 _actualInterestAfter = lendFacet.pendingInterest(address(weth));
    assertEq(_actualInterestAfter, 10e18);
    lendFacet.accureInterest(address(weth));
    (, uint256 _actualDebtAmount) = borrowFacet.getDebt(
      BOB,
      subAccount0,
      address(weth)
    );
    assertEq(_actualDebtAmount, _expectedDebtAmount);

    // FIXME last accuretime
    uint256 _actualAccureTime = lendFacet.getDebtLastAccureTime(address(weth));
    console.log("timestamp", block.timestamp);
    assertEq(_actualAccureTime, 11);
  }

  /* 
  alice deposit
  bob borrow
  time passed
  alice withdraw 
  assert alice should get interest
  assert bob debt increasing
   */

  /* 2 borrower 1 depositors
    alice deposit
    bob borrow

  */

  /*  1 borrower 2 depositors
   */

  /* 2 borrower 2 depositors
      alice deposit
      bob borrowed
      10sec passed cat deposit
      10sec ddd borrowed
      after accure debt
      verify is it not be able more 
      verify ddd interest < bob  (borrow the same amount)
      verify cat interest < alice (deposit same amount)
      
    */
}
