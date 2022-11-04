// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, console } from "./MoneyMarket_BaseTest.t.sol";

// interfaces
import { INonCollatBorrowFacet, LibDoublyLinkedList } from "../../contracts/money-market/facets/NonCollatBorrowFacet.sol";
import { IAdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";
import { TripleSlopeModel6, IInterestRateModel } from "../../contracts/money-market/interest-models/TripleSlopeModel6.sol";
import { TripleSlopeModel7 } from "../../contracts/money-market/interest-models/TripleSlopeModel7.sol";

contract MoneyMarket_NonCollatBorrowFacetTest is MoneyMarket_BaseTest {
  MockERC20 mockToken;

  function setUp() public override {
    super.setUp();

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    adminFacet.setNonCollatBorrower(ALICE, true);
    adminFacet.setNonCollatBorrower(BOB, true);

    vm.startPrank(ALICE);
    lendFacet.deposit(address(weth), 50 ether);
    lendFacet.deposit(address(usdc), 20 ether);
    lendFacet.deposit(address(isolateToken), 20 ether);
    vm.stopPrank();

    TripleSlopeModel6 tripleSlope6 = new TripleSlopeModel6();
    TripleSlopeModel7 tripleSlope7 = new TripleSlopeModel7();
    adminFacet.setNonCollatInterestModel(ALICE, address(weth), address(tripleSlope6));
    adminFacet.setNonCollatInterestModel(BOB, address(weth), address(tripleSlope7));
  }

  function testCorrectness_WhenUserBorrowTokenFromMM_ShouldTransferTokenToUser() external {
    uint256 _borrowAmount = 10 ether;

    // BOB Borrow _borrowAmount
    vm.startPrank(BOB);
    uint256 _bobBalanceBefore = weth.balanceOf(BOB);
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _borrowAmount);
    vm.stopPrank();

    uint256 _bobBalanceAfter = weth.balanceOf(BOB);

    uint256 _bobDebtAmount = nonCollatBorrowFacet.nonCollatGetDebt(BOB, address(weth));

    assertEq(_bobBalanceAfter - _bobBalanceBefore, _borrowAmount);
    assertEq(_bobDebtAmount, _borrowAmount);

    // ALICE Borrow _borrowAmount
    vm.startPrank(ALICE);
    uint256 _aliceBalanceBefore = weth.balanceOf(ALICE);
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _borrowAmount);
    vm.stopPrank();

    uint256 _aliceBalanceAfter = weth.balanceOf(ALICE);

    uint256 _aliceDebtAmount = nonCollatBorrowFacet.nonCollatGetDebt(ALICE, address(weth));

    assertEq(_aliceBalanceAfter - _aliceBalanceBefore, _borrowAmount);
    assertEq(_aliceDebtAmount, _borrowAmount);

    // total debt should equal sum of alice's and bob's debt
    uint256 _totalDebtAmount = nonCollatBorrowFacet.nonCollatGetTokenDebt(address(weth));

    assertEq(_totalDebtAmount, _borrowAmount * 2);
    assertEq(_bobDebtAmount, _aliceDebtAmount);
  }

  function testRevert_WhenUserBorrowNonAvailableToken_ShouldRevert() external {
    uint256 _borrowAmount = 10 ether;
    vm.startPrank(BOB);
    vm.expectRevert(
      abi.encodeWithSelector(INonCollatBorrowFacet.NonCollatBorrowFacet_InvalidToken.selector, address(mockToken))
    );
    nonCollatBorrowFacet.nonCollatBorrow(address(mockToken), _borrowAmount);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserBorrowMultipleTokens_ListShouldUpdate() external {
    uint256 _aliceBorrowAmount = 10 ether;
    uint256 _aliceBorrowAmount2 = 20 ether;

    vm.startPrank(ALICE);
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    LibDoublyLinkedList.Node[] memory aliceDebtShares = nonCollatBorrowFacet.nonCollatGetDebtValues(ALICE);

    assertEq(aliceDebtShares.length, 1);
    assertEq(aliceDebtShares[0].amount, _aliceBorrowAmount);

    vm.startPrank(ALICE);

    // list will be add at the front of linkList
    nonCollatBorrowFacet.nonCollatBorrow(address(usdc), _aliceBorrowAmount2);
    vm.stopPrank();

    aliceDebtShares = nonCollatBorrowFacet.nonCollatGetDebtValues(ALICE);

    assertEq(aliceDebtShares.length, 2);
    assertEq(aliceDebtShares[0].amount, _aliceBorrowAmount2);
    assertEq(aliceDebtShares[1].amount, _aliceBorrowAmount);

    vm.startPrank(ALICE);
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    aliceDebtShares = nonCollatBorrowFacet.nonCollatGetDebtValues(ALICE);

    assertEq(aliceDebtShares.length, 2);
    assertEq(aliceDebtShares[0].amount, _aliceBorrowAmount2);
    assertEq(aliceDebtShares[1].amount, _aliceBorrowAmount * 2, "updated weth");

    uint256 _totalwethDebtAmount = nonCollatBorrowFacet.nonCollatGetTokenDebt(address(weth));

    assertEq(_totalwethDebtAmount, _aliceBorrowAmount * 2);
  }

  function testRevert_WhenUserBorrowMoreThanAvailable_ShouldRevert() external {
    uint256 _aliceBorrowAmount = 30 ether;

    vm.startPrank(ALICE);

    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    LibDoublyLinkedList.Node[] memory aliceDebtShares = nonCollatBorrowFacet.nonCollatGetDebtValues(ALICE);

    assertEq(aliceDebtShares.length, 1);
    assertEq(aliceDebtShares[0].amount, _aliceBorrowAmount);

    vm.startPrank(ALICE);

    vm.expectRevert(
      abi.encodeWithSelector(INonCollatBorrowFacet.NonCollatBorrowFacet_NotEnoughToken.selector, _aliceBorrowAmount * 2)
    );

    // this should reverts as their is only 50 weth but alice try to borrow 60 (20 + (20*2))
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _aliceBorrowAmount * 2);
    vm.stopPrank();
  }

  function testRevert_WhenUserIsNotWhitelisted_ShouldRevert() external {
    vm.startPrank(CAT);

    vm.expectRevert(abi.encodeWithSelector(INonCollatBorrowFacet.NonCollatBorrowFacet_Unauthorized.selector));
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), 10 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenMultipleUserBorrowTokens_MMShouldTransferCorrectIbTokenAmount() external {
    uint256 _bobDepositAmount = 10 ether;
    uint256 _aliceBorrowAmount = 10 ether;

    vm.startPrank(ALICE);
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    vm.startPrank(BOB);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    lendFacet.deposit(address(weth), _bobDepositAmount);

    vm.stopPrank();

    assertEq(ibWeth.balanceOf(BOB), 10 ether);
  }

  function testCorrectness_WhenUserRepayLessThanDebtHeHad_ShouldWork() external {
    uint256 _aliceBorrowAmount = 10 ether;
    uint256 _aliceRepayAmount = 5 ether;

    uint256 _bobBorrowAmount = 20 ether;

    vm.startPrank(ALICE);
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _aliceBorrowAmount);

    nonCollatBorrowFacet.nonCollatRepay(ALICE, address(weth), 5 ether);

    vm.stopPrank();

    vm.startPrank(BOB);
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _bobBorrowAmount);

    vm.stopPrank();

    uint256 _aliceRemainingDebt = nonCollatBorrowFacet.nonCollatGetDebt(ALICE, address(weth));

    assertEq(_aliceRemainingDebt, _aliceBorrowAmount - _aliceRepayAmount);

    uint256 _tokenDebt = nonCollatBorrowFacet.nonCollatGetTokenDebt(address(weth));

    assertEq(_tokenDebt, (_aliceBorrowAmount + _bobBorrowAmount) - _aliceRepayAmount);
  }

  function testCorrectness_WhenUserOverRepay_ShouldOnlyRepayTheDebtHeHad() external {
    uint256 _aliceBorrowAmount = 10 ether;
    uint256 _aliceRepayAmount = 15 ether;

    vm.startPrank(ALICE);
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _aliceBorrowAmount);

    uint256 _aliceWethBalanceBefore = weth.balanceOf(ALICE);
    nonCollatBorrowFacet.nonCollatRepay(ALICE, address(weth), _aliceRepayAmount);
    uint256 _aliceWethBalanceAfter = weth.balanceOf(ALICE);
    vm.stopPrank();

    uint256 _aliceRemainingDebt = nonCollatBorrowFacet.nonCollatGetDebt(ALICE, address(weth));

    assertEq(_aliceRemainingDebt, 0);

    assertEq(_aliceWethBalanceBefore - _aliceWethBalanceAfter, _aliceBorrowAmount);

    uint256 _tokenDebt = nonCollatBorrowFacet.nonCollatGetTokenDebt(address(weth));

    assertEq(_tokenDebt, 0);
  }

  function testCorrectness_WhenBobAndAliceBorrowForOneDay_AccureInterestShouldBeCorrected() external {
    uint256 _aliceBorrowAmount = 10 ether;
    uint256 _bobBorrowAmount = 10 ether;

    vm.prank(ALICE);
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _aliceBorrowAmount);

    vm.prank(BOB);
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _bobBorrowAmount);

    uint256 _aliceTokenDebtBefore = nonCollatBorrowFacet.nonCollatGetDebt(ALICE, address(weth));
    uint256 _bobTokenDebtBefore = nonCollatBorrowFacet.nonCollatGetDebt(BOB, address(weth));
    uint256 _tokenDebtBefore = nonCollatBorrowFacet.nonCollatGetTokenDebt(address(weth));

    // before accure interest
    assertEq(_aliceTokenDebtBefore, 10 ether);
    assertEq(_bobTokenDebtBefore, 10 ether);
    assertEq(_tokenDebtBefore, 20 ether);

    vm.warp(1 days + 1);
    // accure interest for alice by 0.001410153102144000 then total debt is 10.001410153102144000
    nonCollatBorrowFacet.accureNonCollatInterest(ALICE, address(weth));
    // accure interest for bob by 0.001956947161824 then total debt is 10.001956947161824
    nonCollatBorrowFacet.accureNonCollatInterest(BOB, address(weth));

    uint256 _aliceTokenDebtAfter = nonCollatBorrowFacet.nonCollatGetDebt(ALICE, address(weth));
    uint256 _bobTokenDebtAfter = nonCollatBorrowFacet.nonCollatGetDebt(BOB, address(weth));

    // total debt should be 10.001410153102144000 + 10.001956947161824 = 20.003367100263968
    uint256 _tokenDebtAfter = nonCollatBorrowFacet.nonCollatGetTokenDebt(address(weth));

    assertEq(_aliceTokenDebtAfter, 10.001410153102144 ether);
    assertEq(_bobTokenDebtAfter, 10.001956947161824 ether);
    assertEq(_tokenDebtAfter, 20.003367100263968 ether);
  }
}
