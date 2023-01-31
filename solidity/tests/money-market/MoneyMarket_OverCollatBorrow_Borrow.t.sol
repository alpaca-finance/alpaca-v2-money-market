// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, console } from "./MoneyMarket_BaseTest.t.sol";

// libraries
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { IBorrowFacet, LibDoublyLinkedList } from "../../contracts/money-market/facets/BorrowFacet.sol";
import { IAdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";

contract MoneyMarket_OverCollatBorrow_BorrowTest is MoneyMarket_BaseTest {
  MockERC20 mockToken;

  function setUp() public override {
    super.setUp();

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    vm.startPrank(ALICE);
    lendFacet.deposit(address(weth), normalizeEther(50 ether, wethDecimal));
    lendFacet.deposit(address(usdc), normalizeEther(20 ether, usdcDecimal));
    lendFacet.deposit(address(btc), normalizeEther(20 ether, btcDecimal));
    lendFacet.deposit(address(cake), normalizeEther(20 ether, cakeDecimal));
    lendFacet.deposit(address(isolateToken), normalizeEther(20 ether, isolateTokenDecimal));
    vm.stopPrank();
  }

  function testCorrectness_WhenUserBorrowTokenFromMM_ShouldTransferTokenToUser() external {
    uint256 _borrowAmount = normalizeEther(10 ether, wethDecimal);

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
    uint256 _borrowAmount = normalizeEther(10 ether, mockToken.decimals());
    vm.startPrank(BOB);
    vm.expectRevert(abi.encodeWithSelector(IBorrowFacet.BorrowFacet_InvalidToken.selector, address(mockToken)));
    borrowFacet.borrow(subAccount0, address(mockToken), _borrowAmount);
    vm.stopPrank();
  }

  function testRevert_WhenUserBorrowTooMuchTokePerSubAccount() external {
    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), normalizeEther(20 ether, wethDecimal));
    borrowFacet.borrow(subAccount0, address(weth), normalizeEther(1 ether, wethDecimal));
    borrowFacet.borrow(subAccount0, address(btc), normalizeEther(1 ether, btcDecimal));
    borrowFacet.borrow(subAccount0, address(usdc), normalizeEther(1 ether, usdcDecimal));

    // now maximum is 3 token per account, when try borrow 4th token should revert
    vm.expectRevert(abi.encodeWithSelector(LibMoneyMarket01.LibMoneyMarket01_NumberOfTokenExceedLimit.selector));
    borrowFacet.borrow(subAccount0, address(cake), normalizeEther(1 ether, cakeDecimal));
    vm.stopPrank();
  }

  function testCorrectness_WhenUserBorrowMultipleTokens_ListAndAccountDebtShareShouldUpdate() external {
    uint256 _aliceBorrowAmount = normalizeEther(10 ether, wethDecimal);
    uint256 _aliceBorrowAmount2 = normalizeEther(20 ether, usdcDecimal);

    vm.startPrank(ALICE);

    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), normalizeEther(100 ether, wethDecimal));

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
    uint256 _aliceBorrowAmount = normalizeEther(20 ether, wethDecimal);

    vm.startPrank(ALICE);

    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), normalizeEther(100 ether, wethDecimal));

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
    uint256 _bobDepositAmount = normalizeEther(10 ether, wethDecimal);
    uint256 _aliceBorrowAmount = normalizeEther(10 ether, wethDecimal);

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), normalizeEther(100 ether, wethDecimal));
    borrowFacet.borrow(subAccount0, address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    vm.startPrank(BOB);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    lendFacet.deposit(address(weth), _bobDepositAmount);

    vm.stopPrank();

    assertEq(ibWeth.balanceOf(BOB), normalizeEther(10 ether, ibWethDecimal));
  }

  function testRevert_WhenBorrowPowerLessThanBorrowingValue_ShouldRevert() external {
    uint256 _aliceCollatAmount = normalizeEther(5 ether, wethDecimal);
    uint256 _aliceBorrowAmount = normalizeEther(5 ether, wethDecimal);

    vm.startPrank(ALICE);

    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), _aliceCollatAmount * 2);

    borrowFacet.borrow(subAccount0, address(weth), _aliceBorrowAmount);
    vm.expectRevert();
    borrowFacet.borrow(subAccount0, address(weth), _aliceBorrowAmount);

    vm.stopPrank();
  }

  function testCorrectness_WhenUserHaveNotBorrow_ShouldAbleToBorrowIsolateAsset() external {
    uint256 _bobIsolateBorrowAmount = normalizeEther(5 ether, isolateTokenDecimal);
    uint256 _bobCollateralAmount = normalizeEther(10 ether, wethDecimal);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _bobCollateralAmount);

    borrowFacet.borrow(subAccount0, address(isolateToken), _bobIsolateBorrowAmount);
    vm.stopPrank();
  }

  function testRevert_WhenUserAlreadyBorrowIsloateToken_ShouldRevertIfTryToBorrowDifferentToken() external {
    uint256 _bobIsolateBorrowAmount = normalizeEther(5 ether, isolateTokenDecimal);
    uint256 _bobCollateralAmount = normalizeEther(20 ether, wethDecimal);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _bobCollateralAmount);

    // first borrow isolate token
    borrowFacet.borrow(subAccount0, address(isolateToken), _bobIsolateBorrowAmount);

    // borrow the isolate token again should passed
    borrowFacet.borrow(subAccount0, address(isolateToken), _bobIsolateBorrowAmount);

    // trying to borrow different asset
    vm.expectRevert(abi.encodeWithSelector(IBorrowFacet.BorrowFacet_InvalidAssetTier.selector));
    borrowFacet.borrow(subAccount0, address(weth), _bobIsolateBorrowAmount);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserBorrowToken_BorrowingPowerAndBorrowedValueShouldCalculateCorrectly() external {
    uint256 _aliceCollatAmount = normalizeEther(5 ether, wethDecimal);

    vm.prank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), _aliceCollatAmount);

    uint256 _borrowingPowerUSDValue = viewFacet.getTotalBorrowingPower(ALICE, subAccount0);

    // add 5 weth, collateralFactor = 9000, weth price = 1
    // _borrowingPowerUSDValue = 5 * 1 * 9000/ 10000 = 4.5 ether USD
    assertEq(_borrowingPowerUSDValue, normalizeEther(4.5 ether, usdDecimal));

    // borrow 2.025 weth => with 9000 borrow factor
    // the used borrowed power should be 2.025 * 10000 / 9000 = 2.25
    // same goes with usdc, used borrowed power also = 2.25
    // sum of both borrowed = 2.25 + 2.25 = 4.5

    vm.startPrank(ALICE);
    borrowFacet.borrow(subAccount0, address(weth), normalizeEther(2.025 ether, wethDecimal));
    borrowFacet.borrow(subAccount0, address(usdc), normalizeEther(2.025 ether, usdcDecimal));
    vm.stopPrank();

    (uint256 _borrowedUSDValue, ) = viewFacet.getTotalUsedBorrowingPower(ALICE, subAccount0);
    assertEq(_borrowedUSDValue, normalizeEther(4.5 ether, usdDecimal));
  }

  function testCorrectness_WhenUserBorrowToken_BorrowingPowerAndBorrowedValueShouldCalculateCorrectlyWithIbTokenCollat()
    external
  {
    uint256 _aliceCollatAmount = normalizeEther(5 ether, wethDecimal);
    uint256 _ibTokenCollatAmount = normalizeEther(5 ether, ibWethDecimal);

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
    assertEq(_borrowingPowerUSDValue, normalizeEther(9 ether, usdDecimal));

    // borrowFactor = 1000, weth price = 1
    // maximumBorrowedUSDValue = _borrowingPowerUSDValue = 9 USD
    // maximumBorrowed weth amount = 9 * 9000/10000 = 8.1
    // _borrowedUSDValue = 8.1 * 10000 /9000 = 9
    vm.prank(ALICE);
    borrowFacet.borrow(subAccount0, address(weth), normalizeEther(8.1 ether, wethDecimal));

    (uint256 _borrowedUSDValue, ) = viewFacet.getTotalUsedBorrowingPower(ALICE, subAccount0);
    assertEq(_borrowedUSDValue, normalizeEther(9 ether, usdDecimal));
  }

  function testCorrectness_WhenUserBorrowToken_BorrowingPowerAndBorrowedValueShouldCalculateCorrectlyWithIbTokenCollat_ibTokenIsNot1to1WithToken()
    external
  {
    uint256 _aliceCollatAmount = normalizeEther(5 ether, wethDecimal);
    uint256 _ibTokenCollatAmount = normalizeEther(5 ether, ibWethDecimal);

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
    lendFacet.deposit(address(weth), normalizeEther(50 ether, wethDecimal));
    vm.prank(moneyMarketDiamond);
    ibWeth.onWithdraw(BOB, BOB, 0, normalizeEther(50 ether, ibWethDecimal));

    uint256 _borrowingPowerUSDValue = viewFacet.getTotalBorrowingPower(ALICE, subAccount0);

    // add 5 weth, collateralFactor = 9000, weth price = 1
    // _borrowingPowerUSDValue = 5 * 1 * 9000 / 10000 = 4.5 ether USD
    // totalSupply = 50
    // totalToken = 105 - 5 (balance - collat) = 100
    // ibCollatAmount = 5
    // borrowIbTokenAmountInToken = 5 * (100 / 50) (ibCollatAmount * (totalToken / totalSupply )) = 10
    // _borrowingPowerUSDValue of ibToken = 10 * 1 * 9000 / 10000 = 9 ether USD
    // then 4.5 + 9 = 13.5
    assertEq(_borrowingPowerUSDValue, normalizeEther(13.5 ether, usdDecimal));

    // borrowFactor = 1000, weth price = 1
    // maximumBorrowedUSDValue = _borrowingPowerUSDValue = 13.5 USD
    // maximumBorrowed weth amount = 13.5 * 9000/10000 = 12.15
    // _borrowedUSDValue = 12.15 * 10000 / 9000 = 13.5
    vm.prank(ALICE);
    borrowFacet.borrow(subAccount0, address(weth), normalizeEther(12.15 ether, wethDecimal));

    (uint256 _borrowedUSDValue, ) = viewFacet.getTotalUsedBorrowingPower(ALICE, subAccount0);
    assertEq(_borrowedUSDValue, normalizeEther(13.5 ether, usdDecimal));
  }

  function testRevert_WhenUserBorrowMoreThanLimit_ShouldRevertBorrowFacetExceedBorrowLimit() external {
    // borrow cap is at 30 weth
    uint256 _borrowAmount = normalizeEther(20 ether, wethDecimal);
    uint256 _bobCollateral = normalizeEther(100 ether, wethDecimal);

    vm.startPrank(BOB);

    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _bobCollateral);

    // first borrow should pass
    borrowFacet.borrow(subAccount0, address(weth), _borrowAmount);

    // the second borrow will revert since it exceed the cap
    vm.expectRevert(abi.encodeWithSelector(IBorrowFacet.BorrowFacet_ExceedBorrowLimit.selector));
    borrowFacet.borrow(subAccount0, address(weth), _borrowAmount);
    vm.stopPrank();
  }

  function testRevert_WhenUserBorrowLessThanMinDebtSize() external {
    // minDebtSize = 0.1 ether, set in mm base test
    // 1 weth = 1 usdc
    // ALICE has 0 weth debt
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), normalizeEther(2 ether, wethDecimal));

    // borrow + debt < minDebtSize should revert
    // 0.01 + 0 < 0.1
    vm.expectRevert(IBorrowFacet.BorrowFacet_BorrowLessThanMinDebtSize.selector);
    borrowFacet.borrow(subAccount0, address(weth), normalizeEther(0.01 ether, wethDecimal));

    // borrow + debt == minDebtSize should not revert
    // 0.1 + 0 == 0.1
    borrowFacet.borrow(subAccount0, address(weth), normalizeEther(0.1 ether, wethDecimal));

    // ALICE has 0.1 weth debt
    // borrow + debt > minDebtSize should not revert
    // 0.01 + 0.1 > 0.1
    borrowFacet.borrow(subAccount0, address(weth), normalizeEther(0.01 ether, wethDecimal));

    (, uint256 _debtAmount) = viewFacet.getOverCollatSubAccountDebt(ALICE, subAccount0, address(weth));
    assertEq(_debtAmount, 0.11 ether);

    // weth price dropped, debt value = 0.11 * 0.8 = 0.88 USD
    mockOracle.setTokenPrice(address(weth), normalizeEther(0.8 ether, wethDecimal));

    // because weth price dropped, borrow + debt < minDebtSize should revert
    // 0.01 + 0.88 < 0.1
    vm.expectRevert(IBorrowFacet.BorrowFacet_BorrowLessThanMinDebtSize.selector);
    borrowFacet.borrow(subAccount0, address(weth), normalizeEther(0.01 ether, wethDecimal));

    // borrow + debt == minDebtSize should not revert
    // 0.12 + 0.88 == 0.1
    borrowFacet.borrow(subAccount0, address(weth), normalizeEther(0.12 ether, wethDecimal));
  }
}
