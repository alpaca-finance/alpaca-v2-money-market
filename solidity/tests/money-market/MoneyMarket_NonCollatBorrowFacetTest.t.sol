// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, console } from "./MoneyMarket_BaseTest.t.sol";

// interfaces
import { INonCollatBorrowFacet, LibDoublyLinkedList } from "../../contracts/money-market/facets/NonCollatBorrowFacet.sol";
import { IAdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";

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
  }

  function testCorrectness_WhenUserBorrowTokenFromMM_ShouldTransferTokenToUser()
    external
  {
    uint256 _borrowAmount = 10 ether;

    // BOB Borrow _borrowAmount
    vm.startPrank(BOB);
    uint256 _bobBalanceBefore = weth.balanceOf(BOB);
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _borrowAmount);
    vm.stopPrank();

    uint256 _bobBalanceAfter = weth.balanceOf(BOB);

    uint256 _bobDebtAmount = nonCollatBorrowFacet.nonCollatGetDebt(
      BOB,
      address(weth)
    );

    assertEq(_bobBalanceAfter - _bobBalanceBefore, _borrowAmount);
    assertEq(_bobDebtAmount, _borrowAmount);

    // ALICE Borrow _borrowAmount
    vm.startPrank(ALICE);
    uint256 _aliceBalanceBefore = weth.balanceOf(ALICE);
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _borrowAmount);
    vm.stopPrank();

    uint256 _aliceBalanceAfter = weth.balanceOf(ALICE);

    uint256 _aliceDebtAmount = nonCollatBorrowFacet.nonCollatGetDebt(
      ALICE,
      address(weth)
    );

    assertEq(_aliceBalanceAfter - _aliceBalanceBefore, _borrowAmount);
    assertEq(_aliceDebtAmount, _borrowAmount);

    // total debt should equal sum of alice's and bob's debt
    uint256 _totalDebtAmount = nonCollatBorrowFacet.nonCollatGetGlobalDebt(
      address(weth)
    );

    assertEq(_totalDebtAmount, _borrowAmount * 2);
    assertEq(_bobDebtAmount, _aliceDebtAmount);
  }

  function testRevert_WhenUserBorrowNonAvailableToken_ShouldRevert() external {
    uint256 _borrowAmount = 10 ether;
    vm.startPrank(BOB);
    vm.expectRevert(
      abi.encodeWithSelector(
        INonCollatBorrowFacet.NonCollatBorrowFacet_InvalidToken.selector,
        address(mockToken)
      )
    );
    nonCollatBorrowFacet.nonCollatBorrow(address(mockToken), _borrowAmount);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserBorrowMultipleTokens_ListShouldUpdate()
    external
  {
    uint256 _aliceBorrowAmount = 10 ether;
    uint256 _aliceBorrowAmount2 = 20 ether;

    vm.startPrank(ALICE);

    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    LibDoublyLinkedList.Node[] memory aliceDebtShares = nonCollatBorrowFacet
      .nonCollatGetDebtValues(ALICE);

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

    uint256 _totalwethDebtAmount = nonCollatBorrowFacet.nonCollatGetGlobalDebt(
      address(weth)
    );

    assertEq(_totalwethDebtAmount, _aliceBorrowAmount * 2);
  }

  function testRevert_WhenUserBorrowMoreThanAvailable_ShouldRevert() external {
    uint256 _aliceBorrowAmount = 30 ether;

    vm.startPrank(ALICE);

    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    LibDoublyLinkedList.Node[] memory aliceDebtShares = nonCollatBorrowFacet
      .nonCollatGetDebtValues(ALICE);

    assertEq(aliceDebtShares.length, 1);
    assertEq(aliceDebtShares[0].amount, _aliceBorrowAmount);

    vm.startPrank(ALICE);

    vm.expectRevert(
      abi.encodeWithSelector(
        INonCollatBorrowFacet.NonCollatBorrowFacet_NotEnoughToken.selector,
        _aliceBorrowAmount * 2
      )
    );

    // this should reverts as their is only 50 weth but alice try to borrow 60 (20 + (20*2))
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _aliceBorrowAmount * 2);
    vm.stopPrank();
  }

  function testRevert_WhenUserIsNotWhitelisted_ShouldRevert() external {
    vm.startPrank(CAT);

    vm.expectRevert(
      abi.encodeWithSelector(
        INonCollatBorrowFacet.NonCollatBorrowFacet_Unauthorized.selector
      )
    );
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), 10 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenMultipleUserBorrowTokens_MMShouldTransferCorrectIbTokenAmount()
    external
  {
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

  function testCorrectness_WhenUserRepayLessThanDebtHeHad_ShouldWork()
    external
  {
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

    uint256 _aliceRemainingDebt = nonCollatBorrowFacet.nonCollatGetDebt(
      ALICE,
      address(weth)
    );

    assertEq(_aliceRemainingDebt, _aliceBorrowAmount - _aliceRepayAmount);

    uint256 _tokenDebt = nonCollatBorrowFacet.nonCollatGetGlobalDebt(
      address(weth)
    );

    assertEq(
      _tokenDebt,
      (_aliceBorrowAmount + _bobBorrowAmount) - _aliceRepayAmount
    );
  }
}
