// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, console } from "./MoneyMarket_BaseTest.t.sol";

// libraries
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { IBorrowFacet, LibDoublyLinkedList } from "../../contracts/money-market/facets/BorrowFacet.sol";
import { IAdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";

contract MoneyMarket_BorrowFacetTest is MoneyMarket_BaseTest {
  MockERC20 mockToken;

  function setUp() public override {
    super.setUp();

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    vm.startPrank(ALICE);
    lendFacet.deposit(address(weth), 50 ether);
    lendFacet.deposit(address(usdc), 20 ether);
    lendFacet.deposit(address(btc), 20 ether);
    lendFacet.deposit(address(cake), 20 ether);
    lendFacet.deposit(address(isolateToken), 20 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserBorrowTokenFromMM_ShouldTransferTokenToUser() external {
    uint256 _borrowAmount = 10 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _borrowAmount * 2);

    uint256 _bobBalanceBefore = weth.balanceOf(BOB);
    borrowFacet.borrow(subAccount0, address(weth), _borrowAmount);
    vm.stopPrank();

    uint256 _bobBalanceAfter = weth.balanceOf(BOB);

    assertEq(_bobBalanceAfter - _bobBalanceBefore, _borrowAmount);

    uint256 _debtAmount;
    (, _debtAmount) = viewFacet.getOverCollatSubAccountDebt(BOB, subAccount0, address(weth));
    assertEq(_debtAmount, _borrowAmount);
    // sanity check on subaccount1
    (, _debtAmount) = viewFacet.getOverCollatSubAccountDebt(BOB, subAccount1, address(weth));

    assertEq(_debtAmount, 0);
  }

  function testRevert_WhenUserBorrowNonAvailableToken_ShouldRevert() external {
    uint256 _borrowAmount = 10 ether;
    vm.startPrank(BOB);
    vm.expectRevert(abi.encodeWithSelector(IBorrowFacet.BorrowFacet_InvalidToken.selector, address(mockToken)));
    borrowFacet.borrow(subAccount0, address(mockToken), _borrowAmount);
    vm.stopPrank();
  }

  function testRevert_WhenUserBorrowTooMuchTokePerSubAccount() external {
    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), 20 ether);
    borrowFacet.borrow(subAccount0, address(weth), 1 ether);
    borrowFacet.borrow(subAccount0, address(btc), 1 ether);
    borrowFacet.borrow(subAccount0, address(usdc), 1 ether);

    // now maximum is 3 token per account, when try borrow 4th token should revert
    vm.expectRevert(abi.encodeWithSelector(LibMoneyMarket01.LibMoneyMarket01_NumberOfTokenExceedLimit.selector));
    borrowFacet.borrow(subAccount0, address(cake), 1 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserBorrowMultipleTokens_ListAndAccountDebtShareShouldUpdate() external {
    uint256 _aliceBorrowAmount = 10 ether;
    uint256 _aliceBorrowAmount2 = 20 ether;

    vm.startPrank(ALICE);

    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 100 ether);

    borrowFacet.borrow(subAccount0, address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    LibDoublyLinkedList.Node[] memory aliceDebtShares = viewFacet.getOverCollatSubAccountDebtShares(ALICE, subAccount0);

    assertEq(aliceDebtShares.length, 1);
    assertEq(aliceDebtShares[0].amount, _aliceBorrowAmount);

    vm.startPrank(ALICE);

    // list will be add at the front of linkList
    borrowFacet.borrow(subAccount0, address(usdc), _aliceBorrowAmount2);
    vm.stopPrank();

    aliceDebtShares = viewFacet.getOverCollatSubAccountDebtShares(ALICE, subAccount0);

    assertEq(aliceDebtShares.length, 2);
    assertEq(aliceDebtShares[0].amount, _aliceBorrowAmount2);
    assertEq(aliceDebtShares[1].amount, _aliceBorrowAmount);

    vm.startPrank(ALICE);
    borrowFacet.borrow(subAccount0, address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    aliceDebtShares = viewFacet.getOverCollatSubAccountDebtShares(ALICE, subAccount0);

    assertEq(aliceDebtShares.length, 2);
    assertEq(aliceDebtShares[0].amount, _aliceBorrowAmount2);
    assertEq(aliceDebtShares[1].amount, _aliceBorrowAmount * 2, "updated weth");
  }

  function testRevert_WhenUserBorrowMoreThanAvailable_ShouldRevert() external {
    uint256 _aliceBorrowAmount = 20 ether;

    vm.startPrank(ALICE);

    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 100 ether);

    borrowFacet.borrow(subAccount0, address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    LibDoublyLinkedList.Node[] memory aliceDebtShares = viewFacet.getOverCollatSubAccountDebtShares(ALICE, subAccount0);

    assertEq(aliceDebtShares.length, 1);
    assertEq(aliceDebtShares[0].amount, _aliceBorrowAmount);

    vm.startPrank(ALICE);

    // list will be add at the front of linkList
    vm.expectRevert(abi.encodeWithSelector(IBorrowFacet.BorrowFacet_NotEnoughToken.selector, _aliceBorrowAmount * 2));
    borrowFacet.borrow(subAccount0, address(weth), _aliceBorrowAmount * 2);
    vm.stopPrank();
  }

  function testCorrectness_WhenMultipleUserBorrowTokens_MMShouldTransferCorrectIbTokenAmount() external {
    uint256 _bobDepositAmount = 10 ether;
    uint256 _aliceBorrowAmount = 10 ether;

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 100 ether);
    borrowFacet.borrow(subAccount0, address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    vm.startPrank(BOB);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    lendFacet.deposit(address(weth), _bobDepositAmount);

    vm.stopPrank();

    assertEq(ibWeth.balanceOf(BOB), 10 ether);
  }

  function testRevert_WhenBorrowPowerLessThanBorrowingValue_ShouldRevert() external {
    uint256 _aliceCollatAmount = 5 ether;
    uint256 _aliceBorrowAmount = 5 ether;

    vm.startPrank(ALICE);

    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), _aliceCollatAmount * 2);

    borrowFacet.borrow(subAccount0, address(weth), _aliceBorrowAmount);
    vm.expectRevert();
    borrowFacet.borrow(subAccount0, address(weth), _aliceBorrowAmount);

    vm.stopPrank();
  }

  function testCorrectness_WhenUserHaveNotBorrow_ShouldAbleToBorrowIsolateAsset() external {
    vm.warp(86401);

    uint256 _bobIsolateBorrowAmount = 5 ether;
    uint256 _bobCollateralAmount = 10 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _bobCollateralAmount);

    borrowFacet.borrow(subAccount0, address(isolateToken), _bobIsolateBorrowAmount);
    vm.stopPrank();
  }

  function testRevert_WhenUserAlreadyBorrowIsloateToken_ShouldRevertIfTryToBorrowDifferentToken() external {
    vm.warp(86401);

    uint256 _bobIsloateBorrowAmount = 5 ether;
    uint256 _bobCollateralAmount = 20 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _bobCollateralAmount);

    // first borrow isolate token
    borrowFacet.borrow(subAccount0, address(isolateToken), _bobIsloateBorrowAmount);

    // borrow the isolate token again should passed
    borrowFacet.borrow(subAccount0, address(isolateToken), _bobIsloateBorrowAmount);

    // trying to borrow different asset
    vm.expectRevert(abi.encodeWithSelector(IBorrowFacet.BorrowFacet_InvalidAssetTier.selector));
    borrowFacet.borrow(subAccount0, address(weth), _bobIsloateBorrowAmount);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserBorrowToken_BorrowingPowerAndBorrowedValueShouldCalculateCorrectly() external {
    uint256 _aliceCollatAmount = 5 ether;

    vm.prank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), _aliceCollatAmount);

    uint256 _borrowingPowerUSDValue = viewFacet.getTotalBorrowingPower(ALICE, subAccount0);

    // add 5 weth, collateralFactor = 9000, weth price = 1
    // _borrowingPowerUSDValue = 5 * 1 * 9000/ 10000 = 4.5 ether USD
    assertEq(_borrowingPowerUSDValue, 4.5 ether);

    // borrow 2.025 weth => with 9000 borrow factor
    // the used borrowed power should be 2.025 * 10000 / 9000 = 2.25
    // same goes with usdc, used borrowed power also = 2.25
    // sum of both borrowed = 2.25 + 2.25 = 4.5

    vm.startPrank(ALICE);
    borrowFacet.borrow(subAccount0, address(weth), 2.025 ether);
    borrowFacet.borrow(subAccount0, address(usdc), 2.025 ether);
    vm.stopPrank();

    (uint256 _borrowedUSDValue, ) = viewFacet.getTotalUsedBorrowingPower(ALICE, subAccount0);
    assertEq(_borrowedUSDValue, 4.5 ether);
  }

  function testCorrectness_WhenUserBorrowToken_BorrowingPowerAndBorrowedValueShouldCalculateCorrectlyWithIbTokenCollat()
    external
  {
    uint256 _aliceCollatAmount = 5 ether;
    uint256 _ibTokenCollatAmount = 5 ether;

    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, _aliceCollatAmount);
    ibWeth.approve(moneyMarketDiamond, _ibTokenCollatAmount);

    // add by actual token
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), _aliceCollatAmount);
    // add by ibToken
    collateralFacet.addCollateral(ALICE, subAccount0, address(ibWeth), _ibTokenCollatAmount);
    vm.stopPrank();

    uint256 _borrowingPowerUSDValue = viewFacet.getTotalBorrowingPower(ALICE, subAccount0);

    // add 5 weth, collateralFactor = 9000, weth price = 1
    // _borrowingPowerUSDValue = 5 * 1 * 9000 / 10000 = 4.5 ether USD
    // totalSupply = 50
    // totalToken = 55 - 5 (balance - collat) = 50
    // ibCollatAmount = 5
    // borrowIbTokenAmountInToken = 5 * (50 / 50) (ibCollatAmount * (totalSupply / totalToken)) = 5
    // _borrowingPowerUSDValue of ibToken = 5 * 1 * 9000 / 10000 = 4.5 ether USD
    // then 4.5 + 4.5 = 9
    assertEq(_borrowingPowerUSDValue, 9 ether);

    // borrowFactor = 1000, weth price = 1
    // maximumBorrowedUSDValue = _borrowingPowerUSDValue = 9 USD
    // maximumBorrowed weth amount = 9 * 9000/10000 = 8.1
    // _borrowedUSDValue = 8.1 * 10000 /9000 = 9
    vm.prank(ALICE);
    borrowFacet.borrow(subAccount0, address(weth), 8.1 ether);

    (uint256 _borrowedUSDValue, ) = viewFacet.getTotalUsedBorrowingPower(ALICE, subAccount0);
    assertEq(_borrowedUSDValue, 9 ether);
  }

  function testCorrectness_WhenUserBorrowToken_BorrowingPowerAndBorrowedValueShouldCalculateCorrectlyWithIbTokenCollat_ibTokenIsNot1to1WithToken()
    external
  {
    uint256 _aliceCollatAmount = 5 ether;
    uint256 _ibTokenCollatAmount = 5 ether;

    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, _aliceCollatAmount);
    ibWeth.approve(moneyMarketDiamond, _ibTokenCollatAmount);

    // add by actual token
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), _aliceCollatAmount);
    // add by ibToken
    collateralFacet.addCollateral(ALICE, subAccount0, address(ibWeth), _ibTokenCollatAmount);
    vm.stopPrank();

    // manipulate ib price
    vm.prank(BOB);
    lendFacet.deposit(address(weth), 50 ether);
    vm.prank(moneyMarketDiamond);
    ibWeth.onWithdraw(BOB, BOB, 0, 50 ether);

    uint256 _borrowingPowerUSDValue = viewFacet.getTotalBorrowingPower(ALICE, subAccount0);

    // add 5 weth, collateralFactor = 9000, weth price = 1
    // _borrowingPowerUSDValue = 5 * 1 * 9000 / 10000 = 4.5 ether USD
    // totalSupply = 50
    // totalToken = 105 - 5 (balance - collat) = 100
    // ibCollatAmount = 5
    // borrowIbTokenAmountInToken = 5 * (100 / 50) (ibCollatAmount * (totalToken / totalSupply )) = 10
    // _borrowingPowerUSDValue of ibToken = 10 * 1 * 9000 / 10000 = 9 ether USD
    // then 4.5 + 9 = 13.5
    assertEq(_borrowingPowerUSDValue, 13.5 ether);

    // borrowFactor = 1000, weth price = 1
    // maximumBorrowedUSDValue = _borrowingPowerUSDValue = 13.5 USD
    // maximumBorrowed weth amount = 13.5 * 9000/10000 = 12.15
    // _borrowedUSDValue = 12.15 * 10000 / 9000 = 13.5
    vm.prank(ALICE);
    borrowFacet.borrow(subAccount0, address(weth), 12.15 ether);

    (uint256 _borrowedUSDValue, ) = viewFacet.getTotalUsedBorrowingPower(ALICE, subAccount0);
    assertEq(_borrowedUSDValue, 13.5 ether);
  }

  function testRevert_WhenUserBorrowMoreThanLimit_ShouldRevertBorrowFacetExceedBorrowLimit() external {
    // borrow cap is at 30 weth
    uint256 _borrowAmount = 20 ether;
    uint256 _bobCollateral = 100 ether;

    vm.startPrank(BOB);

    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _bobCollateral);

    // first borrow should pass
    borrowFacet.borrow(subAccount0, address(weth), _borrowAmount);

    // the second borrow will revert since it exceed the cap
    vm.expectRevert(abi.encodeWithSelector(IBorrowFacet.BorrowFacet_ExceedBorrowLimit.selector));
    borrowFacet.borrow(subAccount0, address(weth), _borrowAmount);
    vm.stopPrank();
  }
}
