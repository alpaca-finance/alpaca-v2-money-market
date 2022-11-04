// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, console } from "./MoneyMarket_BaseTest.t.sol";

// interfaces
import { IBorrowFacet, LibDoublyLinkedList } from "../../contracts/money-market/facets/BorrowFacet.sol";
import { IAdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";
import { FixedInterestRateModel, IInterestRateModel } from "../../contracts/money-market/interest-models/FixedInterestRateModel.sol";
import { TripleSlopeModel6, IInterestRateModel } from "../../contracts/money-market/interest-models/TripleSlopeModel6.sol";

contract MoneyMarket_AccureInterestTest is MoneyMarket_BaseTest {
  MockERC20 mockToken;

  function setUp() public override {
    super.setUp();

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    FixedInterestRateModel model = new FixedInterestRateModel();
    TripleSlopeModel6 tripleSlope6 = new TripleSlopeModel6();
    adminFacet.setInterestModel(address(weth), address(model));
    adminFacet.setInterestModel(address(usdc), address(tripleSlope6));
    adminFacet.setInterestModel(address(isolateToken), address(model));

    vm.startPrank(ALICE);
    lendFacet.deposit(address(weth), 50 ether);
    lendFacet.deposit(address(usdc), 20 ether);
    lendFacet.deposit(address(isolateToken), 20 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserBorrowTokenFromMM_ShouldBeCorrectPendingInterest() external {
    uint256 _actualInterest = borrowFacet.pendingInterest(address(weth));
    assertEq(_actualInterest, 0);

    uint256 _borrowAmount = 10 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _borrowAmount * 2);

    uint256 _bobBalanceBefore = weth.balanceOf(BOB);
    borrowFacet.borrow(subAccount0, address(weth), _borrowAmount);
    vm.stopPrank();

    uint256 _bobBalanceAfter = weth.balanceOf(BOB);

    assertEq(_bobBalanceAfter - _bobBalanceBefore, _borrowAmount);

    uint256 _debtAmount;
    (, _debtAmount) = borrowFacet.getDebt(BOB, subAccount0, address(weth));
    assertEq(_debtAmount, _borrowAmount);

    vm.warp(block.timestamp + 10);
    uint256 _expectedDebtAmount = 1e18 + _borrowAmount;

    uint256 _actualInterestAfter = borrowFacet.pendingInterest(address(weth));
    assertEq(_actualInterestAfter, 1e18);
    borrowFacet.accureInterest(address(weth));
    (, uint256 _actualDebtAmount) = borrowFacet.getDebt(BOB, subAccount0, address(weth));
    assertEq(_actualDebtAmount, _expectedDebtAmount);

    uint256 _actualAccureTime = borrowFacet.debtLastAccureTime(address(weth));
    assertEq(_actualAccureTime, block.timestamp);
  }

  function testCorrectness_WhenAddCollateralAndUserBorrow_ShouldNotGetInterest() external {
    uint256 _balanceAliceBefore = weth.balanceOf(ALICE);
    uint256 _balanceMMDiamondBefore = weth.balanceOf(moneyMarketDiamond);
    uint256 _aliceCollateralAmount = 10 ether;

    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, _aliceCollateralAmount);
    collateralFacet.addCollateral(ALICE, 0, address(weth), _aliceCollateralAmount);
    vm.stopPrank();

    assertEq(weth.balanceOf(ALICE), _balanceAliceBefore - _aliceCollateralAmount);
    assertEq(weth.balanceOf(moneyMarketDiamond), _balanceMMDiamondBefore + _aliceCollateralAmount);

    vm.warp(block.timestamp + 10);

    //when someone borrow
    uint256 _bobBorrowAmount = 10 ether;
    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _bobBorrowAmount * 2);

    uint256 _bobBalanceBeforeBorrow = weth.balanceOf(BOB);
    borrowFacet.borrow(subAccount0, address(weth), _bobBorrowAmount);

    (, uint256 _actualBobDebtAmountBeforeWarp) = borrowFacet.getDebt(BOB, subAccount0, address(weth));
    assertEq(_actualBobDebtAmountBeforeWarp, _bobBorrowAmount);
    vm.stopPrank();

    uint256 _bobBalanceAfterBorrow = weth.balanceOf(BOB);

    assertEq(_bobBalanceAfterBorrow - _bobBalanceBeforeBorrow, _bobBorrowAmount);
    vm.warp(block.timestamp + 10);
    borrowFacet.accureInterest(address(weth));
    (, uint256 _actualBobDebtAmountAfter) = borrowFacet.getDebt(BOB, subAccount0, address(weth));

    assertEq(_actualBobDebtAmountAfter - _actualBobDebtAmountBeforeWarp, 1 ether);

    uint256 wethAliceBeforeWithdraw = weth.balanceOf(ALICE);
    vm.prank(ALICE);
    collateralFacet.removeCollateral(0, address(weth), 10 ether);
    uint256 wethAliceAfterWithdraw = weth.balanceOf(ALICE);
    assertEq(wethAliceAfterWithdraw - wethAliceBeforeWithdraw, 10 ether);
    LibDoublyLinkedList.Node[] memory collats = collateralFacet.getCollaterals(ALICE, 0);
    assertEq(collats.length, 0);
  }

  /* 2 borrower 1 depositors
    alice deposit
    bob borrow
  */
  function testCorrectness_WhenMultipleUserBorrow_ShouldAccureInterestCorrectly() external {
    // BOB add ALICE add collateral
    uint256 _actualInterest = borrowFacet.pendingInterest(address(weth));
    assertEq(_actualInterest, 0);

    uint256 _borrowAmount = 10 ether;

    vm.prank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _borrowAmount * 2);

    vm.prank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), _borrowAmount * 2);

    // BOB borrow
    vm.startPrank(BOB);
    uint256 _bobBalanceBefore = weth.balanceOf(BOB);
    borrowFacet.borrow(subAccount0, address(weth), _borrowAmount);
    vm.stopPrank();

    uint256 _bobBalanceAfter = weth.balanceOf(BOB);

    assertEq(_bobBalanceAfter - _bobBalanceBefore, _borrowAmount);
    vm.stopPrank();

    // time past
    vm.warp(block.timestamp + 10);
    // ALICE borrow and bob's interest accure
    vm.startPrank(ALICE);
    uint256 _aliceBalanceBefore = weth.balanceOf(ALICE);
    borrowFacet.borrow(subAccount0, address(weth), _borrowAmount);
    vm.stopPrank();

    uint256 _aliceBalanceAfter = weth.balanceOf(ALICE);

    assertEq(_aliceBalanceAfter - _aliceBalanceBefore, _borrowAmount);
    assertEq(borrowFacet.debtLastAccureTime(address(weth)), block.timestamp);

    // assert BOB
    (, uint256 _bobActualDebtAmount) = borrowFacet.getDebt(BOB, subAccount0, address(weth));
    // bob borrow 10 with 0.1 interest rate per sec
    // precision loss
    // 10 seconed passed _bobExpectedDebtAmount = 10 + (10*0.1) ~ 11 = 10999999999999999999
    uint256 _bobExpectedDebtAmount = 10.999999999999999999 ether;
    assertEq(_bobActualDebtAmount, _bobExpectedDebtAmount);

    // assert ALICE
    (, uint256 _aliceActualDebtAmount) = borrowFacet.getDebt(ALICE, subAccount0, address(weth));
    // _aliceExpectedDebtAmount should be 10 ether
    // so _aliceExpectedDebtAmount = 10 ether
    uint256 _aliceExpectedDebtAmount = 10 ether;
    assertEq(_aliceActualDebtAmount, _aliceExpectedDebtAmount, "Alice debtAmount missmatch");

    // assert Global
    // from BOB 10 + 1, Alice 10
    assertEq(borrowFacet.debtValues(address(weth)), 21 ether, "Global debtValues missmatch");

    // assert IB exchange rate change
    // alice wthdraw 10 ibWeth, totalToken = 51, totalSupply = 50
    // alice should get = 10 * 51 / 50 = 10.2 eth
    uint256 _expectdAmount = 10.2 ether;
    _aliceBalanceBefore = weth.balanceOf(ALICE);
    vm.prank(ALICE);
    lendFacet.withdraw(address(ibWeth), _borrowAmount);
    _aliceBalanceAfter = weth.balanceOf(ALICE);

    assertEq(_aliceBalanceAfter - _aliceBalanceBefore, _expectdAmount, "ALICE weth balance missmatch");
  }

  function testCorrectness_WhenUserCallDeposit_InterestShouldAccrue() external {
    uint256 _timeStampBefore = block.timestamp;
    uint256 _secondPassed = 10;
    assertEq(borrowFacet.debtLastAccureTime(address(weth)), _timeStampBefore);

    vm.warp(block.timestamp + _secondPassed);

    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, 10 ether);
    lendFacet.deposit(address(weth), 10 ether);
    vm.stopPrank();

    assertEq(borrowFacet.debtLastAccureTime(address(weth)), _timeStampBefore + _secondPassed);
  }

  function testCorrectness_WhenUserCallWithdraw_InterestShouldAccrue() external {
    uint256 _timeStampBefore = block.timestamp;
    uint256 _secondPassed = 10;

    vm.prank(ALICE);
    lendFacet.deposit(address(weth), 10 ether);

    assertEq(borrowFacet.debtLastAccureTime(address(weth)), _timeStampBefore);

    vm.warp(block.timestamp + _secondPassed);

    vm.prank(ALICE);
    lendFacet.withdraw(address(ibWeth), 10 ether);

    assertEq(borrowFacet.debtLastAccureTime(address(weth)), _timeStampBefore + _secondPassed);
  }

  function testCorrectness_WhenMMUseTripleSlopeInterestModel_InterestShouldAccureCorrectly() external {
    // BOB add ALICE add collateral
    uint256 _actualInterest = borrowFacet.pendingInterest(address(usdc));
    assertEq(_actualInterest, 0);

    uint256 _borrowAmount = 10 ether;

    vm.prank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _borrowAmount * 2);

    vm.prank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(usdc), _borrowAmount * 2);

    // BOB borrow
    vm.startPrank(BOB);
    uint256 _bobBalanceBefore = usdc.balanceOf(BOB);
    borrowFacet.borrow(subAccount0, address(usdc), _borrowAmount);
    vm.stopPrank();

    uint256 _bobBalanceAfter = usdc.balanceOf(BOB);

    assertEq(_bobBalanceAfter - _bobBalanceBefore, _borrowAmount);
    vm.stopPrank();

    // time past
    uint256 _secondPassed = 1 days;
    vm.warp(block.timestamp + _secondPassed);
    // ALICE borrow and bob's interest accure
    vm.startPrank(ALICE);
    uint256 _aliceBalanceBefore = usdc.balanceOf(ALICE);
    borrowFacet.borrow(subAccount0, address(usdc), _borrowAmount);
    vm.stopPrank();

    uint256 _aliceBalanceAfter = usdc.balanceOf(ALICE);

    assertEq(_aliceBalanceAfter - _aliceBalanceBefore, _borrowAmount);
    assertEq(borrowFacet.debtLastAccureTime(address(usdc)), block.timestamp);

    // assert BOB
    (, uint256 _bobActualDebtAmount) = borrowFacet.getDebt(BOB, subAccount0, address(usdc));
    // bob borrow 10 usdc, pool has 20 usdc, utilization = 50%
    // interest rate = 10.2941176456512000% per year
    // 1 day passed _bobExpectedDebtAmount = debtAmount + (debtAmount * seconedPass * ratePerSec)
    // = 10 + (10 * 1 * 0.102941176456512000/365) ~ 10.002820306204288000 = 10.002820306204287999
    uint256 _bobExpectedDebtAmount = 10.002820306204287999 ether;
    assertEq(_bobActualDebtAmount, _bobExpectedDebtAmount);

    // assert ALICE
    (, uint256 _aliceActualDebtAmount) = borrowFacet.getDebt(ALICE, subAccount0, address(usdc));
    // _aliceExpectedDebtAmount should be 10 ether
    // so _aliceExpectedDebtAmount = 10 ether
    uint256 _aliceExpectedDebtAmount = 10 ether;
    assertEq(_aliceActualDebtAmount, _aliceExpectedDebtAmount, "Alice debtAmount missmatch");

    // // assert Global
    // from BOB 10 + 0.002820306204288 =, Alice 10 = 20.002820306204288
    assertEq(borrowFacet.debtValues(address(usdc)), 20.002820306204288 ether, "Global debtValues missmatch");

    // assert IB exchange rate change
    // alice wthdraw 10 ibUSDC, totalToken = 20.002820306204288, totalSupply = 20
    // alice should get = 10 * 20.002820306204288 / 20 = 10.2 eth
    uint256 _expectdAmount = 10.001410153102144 ether;
    _aliceBalanceBefore = usdc.balanceOf(ALICE);
    vm.prank(ALICE);
    lendFacet.withdraw(address(ibUsdc), _borrowAmount);
    _aliceBalanceAfter = usdc.balanceOf(ALICE);

    assertEq(_aliceBalanceAfter - _aliceBalanceBefore, _expectdAmount, "ALICE weth balance missmatch");
  }
}
