// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, console } from "./MoneyMarket_BaseTest.t.sol";

// interfaces
import { IBorrowFacet, LibDoublyLinkedList } from "../../contracts/money-market/facets/BorrowFacet.sol";
import { IAdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";

contract MoneyMarket_BorrowFacetTest is MoneyMarket_BaseTest {
  uint256 subAccount0 = 0;
  uint256 subAccount1 = 1;
  MockERC20 mockToken;

  function setUp() public override {
    super.setUp();

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    vm.startPrank(ALICE);
    lendFacet.deposit(address(weth), 20 ether);
    lendFacet.deposit(address(usdc), 20 ether);
    lendFacet.deposit(address(isolateToken), 20 ether);
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
      _borrowAmount * 2
    );

    uint256 _bobBalanceBefore = weth.balanceOf(BOB);
    borrowFacet.borrow(BOB, subAccount0, address(weth), _borrowAmount);
    vm.stopPrank();

    uint256 _bobBalanceAfter = weth.balanceOf(BOB);

    assertEq(_bobBalanceAfter - _bobBalanceBefore, _borrowAmount);

    uint256 _debtAmount;
    (, _debtAmount) = borrowFacet.getDebt(BOB, subAccount0, address(weth));
    assertEq(_debtAmount, _borrowAmount);
    // sanity check on subaccount1
    (, _debtAmount) = borrowFacet.getDebt(BOB, subAccount1, address(weth));

    assertEq(_debtAmount, 0);
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

  function testCorrectness_WhenMultipleUserBorrowTokens_MMShouldTransferCorrectIbTokenAmount()
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
    lendFacet.deposit(address(weth), _bobDepositAmount);

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
      _aliceCollatAmount * 2
    );

    borrowFacet.borrow(ALICE, subAccount0, address(weth), _aliceBorrowAmount);
    vm.expectRevert();
    borrowFacet.borrow(ALICE, subAccount0, address(weth), _aliceBorrowAmount);

    vm.stopPrank();
  }

  function testCorrectness_WhenUserHaveNotBorrow_ShouldAbleToBorrowIsolateAsset()
    external
  {
    uint256 _bobIsloateBorrowAmount = 5 ether;
    uint256 _bobCollateralAmount = 10 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(
      BOB,
      subAccount0,
      address(weth),
      _bobCollateralAmount
    );

    borrowFacet.borrow(
      BOB,
      subAccount0,
      address(isolateToken),
      _bobIsloateBorrowAmount
    );
    vm.stopPrank();
  }

  function testRevert_WhenUserAlreadyBorrowIsloateToken_ShouldRevertIfTryToBorrowDifferentToken()
    external
  {
    uint256 _bobIsloateBorrowAmount = 5 ether;
    uint256 _bobCollateralAmount = 20 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(
      BOB,
      subAccount0,
      address(weth),
      _bobCollateralAmount
    );

    // first borrow isolate token
    borrowFacet.borrow(
      BOB,
      subAccount0,
      address(isolateToken),
      _bobIsloateBorrowAmount
    );

    // borrow the isolate token again should passed
    borrowFacet.borrow(
      BOB,
      subAccount0,
      address(isolateToken),
      _bobIsloateBorrowAmount
    );

    // trying to borrow different asset
    vm.expectRevert(
      abi.encodeWithSelector(IBorrowFacet.BorrowFacet_InvalidAssetTier.selector)
    );
    borrowFacet.borrow(
      BOB,
      subAccount0,
      address(weth),
      _bobIsloateBorrowAmount
    );
    vm.stopPrank();
  }

  function testCorrectness_WhenUserBorrowToken_BorrowingPowerAndBorrowedValueShouldCalculateCorrectly()
    external
  {
    uint256 _aliceCollatAmount = 5 ether;

    vm.prank(ALICE);
    collateralFacet.addCollateral(
      ALICE,
      subAccount0,
      address(weth),
      _aliceCollatAmount
    );

    uint256 _borrowingPowerUSDValue = borrowFacet.getTotalBorrowingPower(
      ALICE,
      subAccount0
    );

    // add 5 weth, collateralFactor = 9000, weth price = 1
    // _borrowingPowerUSDValue = 5 * 1 * 9000/ 10000 = 4.5 ether USD
    assertEq(_borrowingPowerUSDValue, 4.5 ether);

    // borrowFactor = 1000, weth price = 1
    // maximumBorrowedUSDValue = _borrowingPowerUSDValue = 4.5 USD
    // maximumBorrowed weth amount = 4.5 * 10000/(10000 + 1000) ~ 4.09090909090909
    // _borrowedUSDValue = 4.09090909090909 * (10000 + 1000)/10000 = 4.499999999999999
    vm.prank(ALICE);
    borrowFacet.borrow(
      ALICE,
      subAccount0,
      address(weth),
      4.09090909090909 ether
    );

    (uint256 _borrowedUSDValue, ) = borrowFacet.getTotalUsedBorrowedPower(
      ALICE,
      subAccount0
    );
    assertEq(_borrowedUSDValue, 4.499999999999999 ether);
  }
}
