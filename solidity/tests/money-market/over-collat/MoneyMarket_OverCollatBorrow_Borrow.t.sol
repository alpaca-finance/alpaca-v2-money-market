// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest, MockERC20, console } from "../MoneyMarket_BaseTest.t.sol";

// libraries
import { LibMoneyMarket01 } from "../../../contracts/money-market/libraries/LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "../../../contracts/money-market/libraries/LibDoublyLinkedList.sol";
// interfaces
import { IBorrowFacet } from "../../../contracts/money-market/interfaces/IBorrowFacet.sol";
import { IAdminFacet } from "../../../contracts/money-market/interfaces/IAdminFacet.sol";
import { IMiniFL } from "../../../contracts/money-market/interfaces/IMiniFL.sol";

contract MoneyMarket_OverCollatBorrow_BorrowTest is MoneyMarket_BaseTest {
  MockERC20 mockToken;

  function setUp() public override {
    super.setUp();

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    vm.startPrank(ALICE);
    accountManager.deposit(address(weth), normalizeEther(50 ether, wethDecimal));
    accountManager.deposit(address(usdc), normalizeEther(20 ether, usdcDecimal));
    accountManager.deposit(address(btc), normalizeEther(20 ether, btcDecimal));
    accountManager.deposit(address(cake), normalizeEther(20 ether, cakeDecimal));
    accountManager.deposit(address(isolateToken), normalizeEther(20 ether, isolateTokenDecimal));
    vm.stopPrank();
  }

  function testCorrectness_WhenUserBorrowTokenFromMM_ShouldTransferTokenToUser() external {
    uint256 _borrowAmount = normalizeEther(10 ether, wethDecimal);

    vm.startPrank(BOB);
    accountManager.addCollateralFor(BOB, subAccount0, address(weth), _borrowAmount * 2);

    uint256 _bobBalanceBefore = weth.balanceOf(BOB);
    accountManager.borrow(subAccount0, address(weth), _borrowAmount);
    vm.stopPrank();

    uint256 _bobBalanceAfter = weth.balanceOf(BOB);

    assertEq(_bobBalanceAfter - _bobBalanceBefore, _borrowAmount);

    uint256 _debtAmount;
    (, _debtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(BOB, subAccount0, address(weth));
    assertEq(_debtAmount, _borrowAmount);
    // sanity check on subaccount1
    (, _debtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(BOB, subAccount1, address(weth));

    assertEq(_debtAmount, 0);
  }

  function testCorrectness_WhenUserBorrowETHFromMM_ShouldTransferETHToUser() external {
    uint256 _borrowAmount = 10 ether;
    vm.prank(ALICE);
    accountManager.depositETH{ value: 50 ether }();
    mockOracle.setTokenPrice(address(wNativeToken), 1 ether);

    vm.startPrank(BOB);
    accountManager.addCollateralFor(BOB, subAccount0, address(weth), _borrowAmount * 2);

    uint256 _bobBalanceBefore = BOB.balance;
    uint256 _moneyMarketBalanceBefore = wNativeToken.balanceOf(moneyMarketDiamond);

    accountManager.borrowETH(subAccount0, _borrowAmount);
    vm.stopPrank();

    uint256 _bobBalanceAfter = BOB.balance;
    uint256 _moneyMarketBalanceAfter = wNativeToken.balanceOf(moneyMarketDiamond);

    assertEq(_bobBalanceAfter - _bobBalanceBefore, _borrowAmount);
    assertEq(_moneyMarketBalanceBefore - _moneyMarketBalanceAfter, _borrowAmount);
  }

  function testRevert_WhenUserBorrowNonAvailableToken_ShouldRevert() external {
    uint256 _borrowAmount = normalizeEther(10 ether, mockToken.decimals());
    vm.startPrank(BOB);
    vm.expectRevert(abi.encodeWithSelector(IBorrowFacet.BorrowFacet_InvalidToken.selector, address(mockToken)));
    accountManager.borrow(subAccount0, address(mockToken), _borrowAmount);
    vm.stopPrank();
  }

  function testRevert_WhenUserBorrowTooMuchTokePerSubAccount() external {
    vm.startPrank(BOB);
    accountManager.addCollateralFor(BOB, subAccount0, address(weth), normalizeEther(20 ether, wethDecimal));
    accountManager.borrow(subAccount0, address(weth), normalizeEther(1 ether, wethDecimal));
    accountManager.borrow(subAccount0, address(btc), normalizeEther(1 ether, btcDecimal));
    accountManager.borrow(subAccount0, address(usdc), normalizeEther(1 ether, usdcDecimal));

    // now maximum is 3 token per account, when try borrow 4th token should revert
    vm.expectRevert(abi.encodeWithSelector(LibMoneyMarket01.LibMoneyMarket01_NumberOfTokenExceedLimit.selector));
    accountManager.borrow(subAccount0, address(cake), normalizeEther(1 ether, cakeDecimal));
    vm.stopPrank();
  }

  function testCorrectness_WhenUserBorrowMultipleTokens_ListAndAccountDebtShareShouldUpdate() external {
    uint256 _aliceBorrowAmount = normalizeEther(10 ether, wethDecimal);
    uint256 _aliceBorrowAmount2 = normalizeEther(20 ether, usdcDecimal);

    vm.startPrank(ALICE);

    accountManager.addCollateralFor(ALICE, subAccount0, address(weth), normalizeEther(100 ether, wethDecimal));

    accountManager.borrow(subAccount0, address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    LibDoublyLinkedList.Node[] memory aliceDebtShares = viewFacet.getOverCollatDebtSharesOf(ALICE, subAccount0);

    assertEq(aliceDebtShares.length, 1);
    assertEq(aliceDebtShares[0].amount, _aliceBorrowAmount);

    vm.startPrank(ALICE);

    // list will be add at the front of linkList
    accountManager.borrow(subAccount0, address(usdc), _aliceBorrowAmount2);
    vm.stopPrank();

    aliceDebtShares = viewFacet.getOverCollatDebtSharesOf(ALICE, subAccount0);

    assertEq(aliceDebtShares.length, 2);
    assertEq(aliceDebtShares[0].amount, _aliceBorrowAmount2);
    assertEq(aliceDebtShares[1].amount, _aliceBorrowAmount);

    vm.startPrank(ALICE);
    accountManager.borrow(subAccount0, address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    aliceDebtShares = viewFacet.getOverCollatDebtSharesOf(ALICE, subAccount0);

    assertEq(aliceDebtShares.length, 2);
    assertEq(aliceDebtShares[0].amount, _aliceBorrowAmount2);
    assertEq(aliceDebtShares[1].amount, _aliceBorrowAmount * 2, "updated weth");
  }

  function testRevert_WhenUserBorrowMoreThanAvailable_ShouldRevert() external {
    uint256 _aliceBorrowAmount = normalizeEther(20 ether, wethDecimal);

    vm.startPrank(ALICE);

    accountManager.addCollateralFor(ALICE, subAccount0, address(weth), normalizeEther(100 ether, wethDecimal));

    accountManager.borrow(subAccount0, address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    LibDoublyLinkedList.Node[] memory aliceDebtShares = viewFacet.getOverCollatDebtSharesOf(ALICE, subAccount0);

    assertEq(aliceDebtShares.length, 1);
    assertEq(aliceDebtShares[0].amount, _aliceBorrowAmount);

    vm.startPrank(ALICE);

    // list will be add at the front of linkList
    vm.expectRevert(abi.encodeWithSelector(IBorrowFacet.BorrowFacet_NotEnoughToken.selector, _aliceBorrowAmount * 2));
    accountManager.borrow(subAccount0, address(weth), _aliceBorrowAmount * 2);
    vm.stopPrank();
  }

  function testCorrectness_WhenMultipleUserBorrowTokens_MMShouldTransferCorrectIbTokenAmount() external {
    uint256 _bobDepositAmount = normalizeEther(10 ether, wethDecimal);
    uint256 _aliceBorrowAmount = normalizeEther(10 ether, wethDecimal);

    vm.startPrank(ALICE);
    accountManager.addCollateralFor(ALICE, subAccount0, address(weth), normalizeEther(100 ether, wethDecimal));
    accountManager.borrow(subAccount0, address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    vm.startPrank(BOB);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    accountManager.deposit(address(weth), _bobDepositAmount);

    vm.stopPrank();

    assertEq(ibWeth.balanceOf(BOB), normalizeEther(10 ether, ibWethDecimal));
  }

  function testRevert_WhenBorrowPowerLessThanBorrowingValue_ShouldRevert() external {
    uint256 _aliceCollatAmount = normalizeEther(5 ether, wethDecimal);
    uint256 _aliceBorrowAmount = normalizeEther(5 ether, wethDecimal);

    vm.startPrank(ALICE);

    accountManager.addCollateralFor(ALICE, subAccount0, address(weth), _aliceCollatAmount * 2);

    accountManager.borrow(subAccount0, address(weth), _aliceBorrowAmount);
    vm.expectRevert();
    accountManager.borrow(subAccount0, address(weth), _aliceBorrowAmount);

    vm.stopPrank();
  }

  function testCorrectness_WhenUserHaveNotBorrow_ShouldAbleToBorrowIsolateAsset() external {
    uint256 _bobIsolateBorrowAmount = normalizeEther(5 ether, isolateTokenDecimal);
    uint256 _bobCollateralAmount = normalizeEther(10 ether, wethDecimal);

    vm.startPrank(BOB);
    accountManager.addCollateralFor(BOB, subAccount0, address(weth), _bobCollateralAmount);

    accountManager.borrow(subAccount0, address(isolateToken), _bobIsolateBorrowAmount);
    vm.stopPrank();
  }

  function testRevert_WhenUserAlreadyBorrowIsloateToken_ShouldRevertIfTryToBorrowDifferentToken() external {
    uint256 _bobIsolateBorrowAmount = normalizeEther(5 ether, isolateTokenDecimal);
    uint256 _bobCollateralAmount = normalizeEther(20 ether, wethDecimal);

    vm.startPrank(BOB);
    accountManager.addCollateralFor(BOB, subAccount0, address(weth), _bobCollateralAmount);

    // first borrow isolate token
    accountManager.borrow(subAccount0, address(isolateToken), _bobIsolateBorrowAmount);

    // borrow the isolate token again should passed
    accountManager.borrow(subAccount0, address(isolateToken), _bobIsolateBorrowAmount);

    // trying to borrow different asset
    vm.expectRevert(abi.encodeWithSelector(IBorrowFacet.BorrowFacet_InvalidAssetTier.selector));
    accountManager.borrow(subAccount0, address(weth), _bobIsolateBorrowAmount);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserBorrowToken_BorrowingPowerAndBorrowedValueShouldCalculateCorrectly() external {
    uint256 _aliceCollatAmount = normalizeEther(5 ether, wethDecimal);

    vm.prank(ALICE);
    accountManager.addCollateralFor(ALICE, subAccount0, address(weth), _aliceCollatAmount);

    uint256 _borrowingPower = viewFacet.getTotalBorrowingPower(ALICE, subAccount0);

    // add 5 weth, collateralFactor = 9000, weth price = 1
    // _borrowingPower = 5 * 1 * 9000/ 10000 = 4.5 ether
    assertEq(_borrowingPower, normalizeEther(4.5 ether, usdDecimal));

    // borrow 2.025 weth => with 9000 borrow factor
    // the used borrowed power should be 2.025 * 10000 / 9000 = 2.25
    // same goes with usdc, used borrowed power also = 2.25
    // sum of both borrowed = 2.25 + 2.25 = 4.5

    vm.startPrank(ALICE);
    accountManager.borrow(subAccount0, address(weth), normalizeEther(2.025 ether, wethDecimal));
    accountManager.borrow(subAccount0, address(usdc), normalizeEther(2.025 ether, usdcDecimal));
    vm.stopPrank();

    (uint256 _usedBorrowingPower, ) = viewFacet.getTotalUsedBorrowingPower(ALICE, subAccount0);
    assertEq(_usedBorrowingPower, normalizeEther(4.5 ether, usdDecimal));
  }

  function testCorrectness_WhenUserBorrowToken_BorrowingPowerAndBorrowedValueShouldCalculateCorrectlyWithIbTokenCollat()
    external
  {
    uint256 _aliceCollatAmount = normalizeEther(5 ether, wethDecimal);
    uint256 _aliceDepositAmount = normalizeEther(5 ether, wethDecimal);

    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, _aliceCollatAmount);
    weth.approve(moneyMarketDiamond, _aliceDepositAmount);

    // add by actual token
    accountManager.addCollateralFor(ALICE, subAccount0, address(weth), _aliceCollatAmount);
    // deposit by actual token and add by ibToken
    accountManager.depositAndAddCollateral(subAccount0, address(weth), _aliceDepositAmount);
    vm.stopPrank();

    uint256 _borrowingPower = viewFacet.getTotalBorrowingPower(ALICE, subAccount0);

    // add 5 weth, collateralFactor = 9000, weth price = 1
    // _borrowingPower = 5 * 1 * 9000 / 10000 = 4.5 ether
    // totalSupply = 50 + 5 (init + new deposit) = 55
    // totalToken = 60 - 5 (balance - collat) = 55
    // ibCollatAmount = 5 (from `depositAndAddCollateral(_aliceDepositAmount)`)
    // borrowIbTokenAmountInToken = 5 * (55 / 55) (ibCollatAmount * (totalSupply / totalToken)) = 5
    // _borrowingPower of ibToken = 5 * 1 * 9000 / 10000 = 4.5 ether
    // then 4.5 + 4.5 = 9
    assertEq(_borrowingPower, normalizeEther(9 ether, usdDecimal));

    // borrowFactor = 1000, weth price = 1
    // maximumBorrowedUSDValue = _borrowingPower = 9 USD
    // maximumBorrowed weth amount = 9 * 9000/10000 = 8.1
    // _usedBorrowingPower = 8.1 * 10000 /9000 = 9
    vm.prank(ALICE);
    accountManager.borrow(subAccount0, address(weth), normalizeEther(8.1 ether, wethDecimal));

    (uint256 _usedBorrowingPower, ) = viewFacet.getTotalUsedBorrowingPower(ALICE, subAccount0);
    assertEq(_usedBorrowingPower, normalizeEther(9 ether, usdDecimal));
  }

  function testCorrectness_WhenUserBorrowToken_BorrowingPowerAndBorrowedValueShouldCalculateCorrectlyWithIbTokenCollat_ibTokenIsNot1to1WithToken()
    external
  {
    uint256 _aliceCollatAmount = normalizeEther(5 ether, wethDecimal);
    uint256 _aliceDepositAmount = normalizeEther(5 ether, wethDecimal);

    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, _aliceCollatAmount);
    weth.approve(moneyMarketDiamond, _aliceDepositAmount);

    // add by actual token
    accountManager.addCollateralFor(ALICE, subAccount0, address(weth), _aliceCollatAmount);
    // deposit by actual token and add by ibToken
    accountManager.depositAndAddCollateral(subAccount0, address(weth), _aliceDepositAmount);
    vm.stopPrank();

    // manipulate ib price
    vm.prank(BOB);
    accountManager.deposit(address(weth), normalizeEther(50 ether, wethDecimal));
    vm.prank(moneyMarketDiamond);
    ibWeth.onWithdraw(BOB, BOB, 0, normalizeEther(50 ether, ibWethDecimal));

    uint256 _borrowingPower = viewFacet.getTotalBorrowingPower(ALICE, subAccount0);

    // add 5 weth, collateralFactor = 9000, weth price = 1
    // _borrowingPower = 5 * 1 * 9000 / 10000 = 4.5 ether
    // totalSupply = 50 + 5 (init + new deposit) = 55
    // totalToken = 110 - 5 (balance - collat) = 105
    // ibCollatAmount = 5 (from `depositAndAddCollateral(_aliceDepositAmount)`)
    // borrowIbTokenAmountInToken = 5 * (105 / 55) (ibCollatAmount * (totalToken / totalSupply )) = ~9.55
    // _borrowingPower of ibToken = ~9.545454.. * 1 * 9000 / 10000 = ~8.59 ether
    // then 4.5 + ~8.59 = ~13.09
    assertEq(_borrowingPower, 13090909090909090905);

    // borrowFactor = 1000, weth price = 1
    // maximumBorrowedUSDValue = _borrowingPower = ~13.09 USD
    // maximumBorrowed weth amount = ~13.09 * 9000/10000 = ~11.78
    // _usedBorrowingPower = ~11.78 * 10000 / 9000 = ~13.09
    vm.prank(ALICE);
    accountManager.borrow(subAccount0, address(weth), 11.781818181818181815 ether);

    (uint256 _usedBorrowingPower, ) = viewFacet.getTotalUsedBorrowingPower(ALICE, subAccount0);
    assertEq(_usedBorrowingPower, 13090909090909090905);
  }

  function testRevert_WhenUserBorrowMoreThanLimit_ShouldRevertBorrowFacetExceedBorrowLimit() external {
    // borrow cap is at 30 weth
    uint256 _borrowAmount = normalizeEther(20 ether, wethDecimal);
    uint256 _bobCollateral = normalizeEther(100 ether, wethDecimal);

    vm.startPrank(BOB);

    accountManager.addCollateralFor(BOB, subAccount0, address(weth), _bobCollateral);

    // first borrow should pass
    accountManager.borrow(subAccount0, address(weth), _borrowAmount);

    // the second borrow will revert since it exceed the cap
    vm.expectRevert(abi.encodeWithSelector(IBorrowFacet.BorrowFacet_ExceedBorrowLimit.selector));
    accountManager.borrow(subAccount0, address(weth), _borrowAmount);
    vm.stopPrank();
  }

  function testRevert_WhenUserBorrowLessThanMinDebtSize() external {
    // minDebtSize = 0.1 ether, set in mm base test
    // 1 weth = 1 usdc
    // ALICE has 0 weth debt
    vm.startPrank(ALICE);
    accountManager.addCollateralFor(ALICE, subAccount0, address(weth), normalizeEther(2 ether, wethDecimal));

    // borrow + debt < minDebtSize should revert
    // 0.01 + 0 < 0.1
    vm.expectRevert(IBorrowFacet.BorrowFacet_BorrowLessThanMinDebtSize.selector);
    accountManager.borrow(subAccount0, address(weth), normalizeEther(0.01 ether, wethDecimal));

    // borrow + debt == minDebtSize should not revert
    // 0.1 + 0 == 0.1
    accountManager.borrow(subAccount0, address(weth), normalizeEther(0.1 ether, wethDecimal));

    // ALICE has 0.1 weth debt
    // borrow + debt > minDebtSize should not revert
    // 0.01 + 0.1 > 0.1
    accountManager.borrow(subAccount0, address(weth), normalizeEther(0.01 ether, wethDecimal));

    (, uint256 _debtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, subAccount0, address(weth));
    assertEq(_debtAmount, 0.11 ether);

    // weth price dropped, debt value = 0.11 * 0.8 = 0.88 USD
    mockOracle.setTokenPrice(address(weth), normalizeEther(0.8 ether, wethDecimal));

    // because weth price dropped, borrow + debt < minDebtSize should revert
    // 0.01 + 0.88 < 0.1
    vm.expectRevert(IBorrowFacet.BorrowFacet_BorrowLessThanMinDebtSize.selector);
    accountManager.borrow(subAccount0, address(weth), normalizeEther(0.01 ether, wethDecimal));

    // borrow + debt == minDebtSize should not revert
    // 0.12 + 0.88 == 0.1
    accountManager.borrow(subAccount0, address(weth), normalizeEther(0.12 ether, wethDecimal));

    vm.stopPrank();
  }

  function testRevert_UserBorrowWhenMMOnEmergencyPaused_ShouldRevert() external {
    adminFacet.setEmergencyPaused(true);

    vm.expectRevert(abi.encodeWithSelector(LibMoneyMarket01.LibMoneyMarket01_EmergencyPaused.selector));
    vm.prank(ALICE);
    accountManager.borrow(subAccount0, address(weth), normalizeEther(0.01 ether, wethDecimal));
  }

  function testCorrectness_WhenUserBorrowTokenFromMM_MMShouldStakeDebtTokenInMiniFLForUser() external {
    IMiniFL _miniFL = IMiniFL(address(miniFL));

    address _debtToken;
    uint256 _poolId;

    uint256 _borrowAmount = normalizeEther(10 ether, wethDecimal);
    address _borrowToken = address(weth);

    vm.startPrank(BOB);
    accountManager.addCollateralFor(BOB, subAccount0, _borrowToken, _borrowAmount * 2);
    accountManager.borrow(subAccount0, _borrowToken, _borrowAmount);
    vm.stopPrank();

    // check token is exist in miniFL
    _debtToken = viewFacet.getDebtTokenFromToken(_borrowToken);
    _poolId = viewFacet.getMiniFLPoolIdOfToken(_debtToken);
    assertEq(_miniFL.getUserTotalAmountOf(_poolId, BOB), _borrowAmount);
  }
}
