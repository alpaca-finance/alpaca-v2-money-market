// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20 } from "./MoneyMarket_BaseTest.t.sol";

// interfaces
import { IBorrowFacet, LibDoublyLinkedList } from "../../contracts/money-market/facets/BorrowFacet.sol";
import { IAdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";

contract MoneyMarket_BorrowFacetTest is MoneyMarket_BaseTest {
  uint256 subAccount0 = 0;
  MockERC20 mockToken;

  function setUp() public override {
    super.setUp();

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    vm.startPrank(ALICE);
    depositFacet.deposit(address(weth), 20 ether);
    depositFacet.deposit(address(usdc), 20 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserBorrowTokenFromMM_ShouldTransferTokenToUser()
    external
  {
    uint256 _borrowAmount = 10 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(
      BOB,
      subAccount0,
      address(weth),
      _borrowAmount
    );

    uint256 _bobBalanceBefore = weth.balanceOf(BOB);
    borrowFacet.borrow(BOB, subAccount0, address(weth), _borrowAmount);
    vm.stopPrank();

    uint256 _bobBalanceAfter = weth.balanceOf(BOB);

    assertEq(_bobBalanceAfter - _bobBalanceBefore, _borrowAmount);
  }

  function testRevert_WhenUserBorrowNonAvailableToken_ShouldRevert() external {
    uint256 _borrowAmount = 10 ether;
    vm.startPrank(BOB);
    vm.expectRevert(
      abi.encodeWithSelector(
        IBorrowFacet.BorrowFacet_InvalidToken.selector,
        address(mockToken)
      )
    );
    borrowFacet.borrow(BOB, subAccount0, address(mockToken), _borrowAmount);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserBorrowMultipleTokens_ListShouldUpdate()
    external
  {
    uint256 _aliceBorrowAmount = 10 ether;
    uint256 _aliceBorrowAmount2 = 20 ether;

    vm.startPrank(ALICE);

    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 100 ether);

    borrowFacet.borrow(ALICE, subAccount0, address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    LibDoublyLinkedList.Node[] memory aliceDebtShares = borrowFacet
      .getDebtShares(ALICE, subAccount0);

    assertEq(aliceDebtShares.length, 1);
    assertEq(aliceDebtShares[0].amount, _aliceBorrowAmount);

    vm.startPrank(ALICE);

    // list will be add at the front of linkList
    borrowFacet.borrow(ALICE, subAccount0, address(usdc), _aliceBorrowAmount2);
    vm.stopPrank();

    aliceDebtShares = borrowFacet.getDebtShares(ALICE, subAccount0);

    assertEq(aliceDebtShares.length, 2);
    assertEq(aliceDebtShares[0].amount, _aliceBorrowAmount2);
    assertEq(aliceDebtShares[1].amount, _aliceBorrowAmount);

    vm.startPrank(ALICE);
    borrowFacet.borrow(ALICE, subAccount0, address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    aliceDebtShares = borrowFacet.getDebtShares(ALICE, subAccount0);

    assertEq(aliceDebtShares.length, 2);
    assertEq(aliceDebtShares[0].amount, _aliceBorrowAmount2);
    assertEq(aliceDebtShares[1].amount, _aliceBorrowAmount * 2, "updated weth");
  }

  function testRevert_WhenUserBorrowMoreThanAvailable_ShouldRevert() external {
    uint256 _aliceBorrowAmount = 20 ether;

    vm.startPrank(ALICE);

    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 100 ether);

    borrowFacet.borrow(ALICE, subAccount0, address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    LibDoublyLinkedList.Node[] memory aliceDebtShares = borrowFacet
      .getDebtShares(ALICE, subAccount0);

    assertEq(aliceDebtShares.length, 1);
    assertEq(aliceDebtShares[0].amount, _aliceBorrowAmount);

    vm.startPrank(ALICE);

    // list will be add at the front of linkList
    vm.expectRevert(
      abi.encodeWithSelector(
        IBorrowFacet.BorrowFacet_NotEnoughToken.selector,
        _aliceBorrowAmount * 2
      )
    );
    borrowFacet.borrow(
      ALICE,
      subAccount0,
      address(weth),
      _aliceBorrowAmount * 2
    );
    vm.stopPrank();
  }

  function testCorrectness_WhenMultipleUserBorrowTokens_MMShouldTransferCorrectIbAmount()
    external
  {
    uint256 _bobDepositAmount = 10 ether;
    uint256 _aliceBorrowAmount = 10 ether;

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 100 ether);
    borrowFacet.borrow(ALICE, subAccount0, address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    vm.startPrank(BOB);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    depositFacet.deposit(address(weth), _bobDepositAmount);

    vm.stopPrank();

    assertEq(ibWeth.balanceOf(BOB), 10 ether);
  }

  function testRevert_WhenBorrowPowerLessThanBorrowingValue_ShouldRevert()
    external
  {
    uint256 _aliceCollatAmount = 5 ether;
    uint256 _aliceBorrowAmount = 5 ether;

    vm.startPrank(ALICE);

    collateralFacet.addCollateral(
      ALICE,
      subAccount0,
      address(weth),
      _aliceCollatAmount
    );

    borrowFacet.borrow(ALICE, subAccount0, address(weth), _aliceBorrowAmount);
    vm.expectRevert();
    borrowFacet.borrow(ALICE, subAccount0, address(weth), _aliceBorrowAmount);

    vm.stopPrank();
  }
}
