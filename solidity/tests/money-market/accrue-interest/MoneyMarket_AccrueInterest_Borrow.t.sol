// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, console } from "../MoneyMarket_BaseTest.t.sol";

// interfaces
import { IBorrowFacet, LibDoublyLinkedList } from "../../../contracts/money-market/facets/BorrowFacet.sol";
import { IAdminFacet } from "../../../contracts/money-market/facets/AdminFacet.sol";
import { FixedInterestRateModel, IInterestRateModel } from "../../../contracts/money-market/interest-models/FixedInterestRateModel.sol";
import { TripleSlopeModel6, IInterestRateModel } from "../../../contracts/money-market/interest-models/TripleSlopeModel6.sol";
import { TripleSlopeModel7 } from "../../../contracts/money-market/interest-models/TripleSlopeModel7.sol";

contract MoneyMarket_AccrueInterest_Borrow is MoneyMarket_BaseTest {
  MockERC20 mockToken;

  function setUp() public override {
    super.setUp();

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    FixedInterestRateModel model = new FixedInterestRateModel(wethDecimal);
    TripleSlopeModel6 tripleSlope6 = new TripleSlopeModel6();
    TripleSlopeModel7 tripleSlope7 = new TripleSlopeModel7();
    adminFacet.setInterestModel(address(weth), address(model));
    adminFacet.setInterestModel(address(usdc), address(tripleSlope6));
    adminFacet.setInterestModel(address(isolateToken), address(model));

    // non collat
    adminFacet.setNonCollatBorrowerOk(ALICE, true);
    adminFacet.setNonCollatBorrowerOk(BOB, true);

    adminFacet.setNonCollatInterestModel(ALICE, address(weth), address(model));
    adminFacet.setNonCollatInterestModel(ALICE, address(btc), address(tripleSlope6));
    adminFacet.setNonCollatInterestModel(BOB, address(weth), address(model));
    adminFacet.setNonCollatInterestModel(BOB, address(btc), address(tripleSlope7));

    vm.startPrank(ALICE);
    accountManager.deposit(address(weth), 50 ether);
    accountManager.deposit(address(btc), 100 ether);
    accountManager.deposit(address(usdc), normalizeEther(20 ether, usdcDecimal));
    accountManager.deposit(address(isolateToken), 20 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserBorrowTokenFromMM_ShouldBeCorrectPendingInterest() external {
    uint256 _actualInterest = viewFacet.getGlobalPendingInterest(address(weth));
    assertEq(_actualInterest, 0);

    uint256 _wethBorrowAmount = 10 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethBorrowAmount * 2);

    uint256 _bobBalanceBefore = weth.balanceOf(BOB);
    borrowFacet.borrow(BOB, subAccount0, address(weth), _wethBorrowAmount);
    vm.stopPrank();

    uint256 _bobBalanceAfter = weth.balanceOf(BOB);

    assertEq(_bobBalanceAfter - _bobBalanceBefore, _wethBorrowAmount);

    uint256 _debtAmount;
    (, _debtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(BOB, subAccount0, address(weth));
    assertEq(_debtAmount, _wethBorrowAmount);

    vm.warp(block.timestamp + 10);

    uint256 _expectedDebtAmount = 1e18 + _wethBorrowAmount;

    uint256 _actualInterestAfter = viewFacet.getGlobalPendingInterest(address(weth));
    assertEq(_actualInterestAfter, 1e18);
    borrowFacet.accrueInterest(address(weth));
    (, uint256 _actualDebtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(BOB, subAccount0, address(weth));
    assertEq(_actualDebtAmount, _expectedDebtAmount);

    uint256 _actualAccrueTime = viewFacet.getDebtLastAccruedAt(address(weth));
    assertEq(_actualAccrueTime, block.timestamp);
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
    borrowFacet.borrow(BOB, subAccount0, address(weth), _bobBorrowAmount);

    (, uint256 _actualBobDebtAmountBeforeWarp) = viewFacet.getOverCollatDebtShareAndAmountOf(
      BOB,
      subAccount0,
      address(weth)
    );
    assertEq(_actualBobDebtAmountBeforeWarp, _bobBorrowAmount);
    vm.stopPrank();

    uint256 _bobBalanceAfterBorrow = weth.balanceOf(BOB);

    assertEq(_bobBalanceAfterBorrow - _bobBalanceBeforeBorrow, _bobBorrowAmount);
    vm.warp(block.timestamp + 10);

    borrowFacet.accrueInterest(address(weth));
    (, uint256 _actualBobDebtAmountAfter) = viewFacet.getOverCollatDebtShareAndAmountOf(
      BOB,
      subAccount0,
      address(weth)
    );

    assertEq(_actualBobDebtAmountAfter - _actualBobDebtAmountBeforeWarp, 1 ether);

    uint256 wethAliceBeforeWithdraw = weth.balanceOf(ALICE);
    vm.prank(ALICE);
    collateralFacet.removeCollateral(ALICE, 0, address(weth), 10 ether);
    uint256 wethAliceAfterWithdraw = weth.balanceOf(ALICE);
    assertEq(wethAliceAfterWithdraw - wethAliceBeforeWithdraw, 10 ether);
    LibDoublyLinkedList.Node[] memory collats = viewFacet.getAllSubAccountCollats(ALICE, 0);
    assertEq(collats.length, 0);
  }

  /* 2 borrower 1 depositors
    alice deposit
    bob borrow
  */
  function testCorrectness_WhenMultipleUserBorrow_ShouldaccrueInterestCorrectly() external {
    // BOB add ALICE add collateral
    uint256 _actualInterest = viewFacet.getGlobalPendingInterest(address(weth));
    assertEq(_actualInterest, 0);

    uint256 _wethBorrowAmount = 10 ether;

    vm.prank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethBorrowAmount * 2);

    vm.prank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), _wethBorrowAmount * 2);

    // BOB borrow
    vm.startPrank(BOB);
    uint256 _bobBalanceBefore = weth.balanceOf(BOB);
    borrowFacet.borrow(BOB, subAccount0, address(weth), _wethBorrowAmount);
    vm.stopPrank();

    uint256 _bobBalanceAfter = weth.balanceOf(BOB);

    assertEq(_bobBalanceAfter - _bobBalanceBefore, _wethBorrowAmount);
    vm.stopPrank();

    // time past
    vm.warp(block.timestamp + 10);

    // ALICE borrow and bob's interest accrue
    vm.startPrank(ALICE);
    uint256 _aliceBalanceBefore = weth.balanceOf(ALICE);
    borrowFacet.borrow(ALICE, subAccount0, address(weth), _wethBorrowAmount);
    vm.stopPrank();

    uint256 _aliceBalanceAfter = weth.balanceOf(ALICE);

    assertEq(_aliceBalanceAfter - _aliceBalanceBefore, _wethBorrowAmount);
    assertEq(viewFacet.getDebtLastAccruedAt(address(weth)), block.timestamp);

    // assert BOB
    (, uint256 _bobActualDebtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(BOB, subAccount0, address(weth));
    // bob borrow 10 with 0.1 interest rate per sec
    // precision loss
    // 10 second passed _bobExpectedDebtAmount = 10 + (10*0.1) ~ 11 = 10999999999999999999
    uint256 _bobExpectedDebtAmount = 10.999999999999999999 ether;
    assertEq(_bobActualDebtAmount, _bobExpectedDebtAmount);

    // assert ALICE
    (, uint256 _aliceActualDebtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, subAccount0, address(weth));
    // _aliceExpectedDebtAmount should be 10 ether
    // so _aliceExpectedDebtAmount = 10 ether
    uint256 _aliceExpectedDebtAmount = 10 ether;
    assertEq(_aliceActualDebtAmount, _aliceExpectedDebtAmount, "Alice debtAmount missmatch");

    // assert Global
    // from BOB 10 + 1, Alice 10
    assertEq(viewFacet.getOverCollatTokenDebtValue(address(weth)), 21 ether, "Global getOverCollatDebtValue missmatch");

    // assert IB exchange rate change
    // alice wthdraw 10 ibWeth, totalToken = 51, totalSupply = 50
    // alice should get = 10 * 51 / 50 = 10.2 eth
    uint256 _expectdAmount = 10.2 ether;
    _aliceBalanceBefore = weth.balanceOf(ALICE);
    vm.prank(ALICE);
    lendFacet.withdraw(ALICE, address(ibWeth), _wethBorrowAmount);
    _aliceBalanceAfter = weth.balanceOf(ALICE);

    assertEq(_aliceBalanceAfter - _aliceBalanceBefore, _expectdAmount, "ALICE weth balance missmatch");
  }

  function testCorrectness_WhenUserCallDeposit_InterestShouldAccrue() external {
    uint256 _timeStampBefore = block.timestamp;
    uint256 _secondPassed = 10;
    assertEq(viewFacet.getDebtLastAccruedAt(address(weth)), _timeStampBefore);

    vm.warp(block.timestamp + _secondPassed);

    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, 10 ether);
    accountManager.deposit(address(weth), 10 ether);
    vm.stopPrank();

    assertEq(viewFacet.getDebtLastAccruedAt(address(weth)), _timeStampBefore + _secondPassed);
  }

  function testCorrectness_WhenUserCallWithdraw_InterestShouldAccrue() external {
    uint256 _timeStampBefore = block.timestamp;
    uint256 _secondPassed = 10;

    vm.prank(ALICE);
    accountManager.deposit(address(weth), 10 ether);

    assertEq(viewFacet.getDebtLastAccruedAt(address(weth)), _timeStampBefore);

    vm.warp(block.timestamp + _secondPassed);

    vm.prank(ALICE);
    lendFacet.withdraw(ALICE, address(ibWeth), 10 ether);

    assertEq(viewFacet.getDebtLastAccruedAt(address(weth)), _timeStampBefore + _secondPassed);
  }

  function testCorrectness_WhenMMUseTripleSlopeInterestModel_InterestShouldAccrueCorrectly() external {
    // BOB add ALICE add collateral
    uint256 _actualInterest = viewFacet.getGlobalPendingInterest(address(usdc));
    assertEq(_actualInterest, 0);

    uint256 _usdcBorrowAmount = normalizeEther(10 ether, usdcDecimal);

    vm.prank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcBorrowAmount * 2);

    vm.prank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(usdc), _usdcBorrowAmount * 2);

    // BOB borrow
    vm.startPrank(BOB);
    uint256 _bobBalanceBefore = usdc.balanceOf(BOB);
    borrowFacet.borrow(BOB, subAccount0, address(usdc), _usdcBorrowAmount);
    vm.stopPrank();

    uint256 _bobBalanceAfter = usdc.balanceOf(BOB);

    assertEq(_bobBalanceAfter - _bobBalanceBefore, _usdcBorrowAmount);
    vm.stopPrank();

    // time past
    uint256 _secondPassed = 1 days;
    vm.warp(block.timestamp + _secondPassed);

    // ALICE borrow and bob's interest accrue
    vm.startPrank(ALICE);
    uint256 _aliceBalanceBefore = usdc.balanceOf(ALICE);
    borrowFacet.borrow(ALICE, subAccount0, address(usdc), _usdcBorrowAmount);
    vm.stopPrank();

    uint256 _aliceBalanceAfter = usdc.balanceOf(ALICE);

    assertEq(_aliceBalanceAfter - _aliceBalanceBefore, _usdcBorrowAmount);
    assertEq(viewFacet.getDebtLastAccruedAt(address(usdc)), block.timestamp);

    // assert BOB
    (, uint256 _bobActualDebtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(BOB, subAccount0, address(usdc));
    // bob borrow 10 usdc, pool has 20 usdc, utilization = 50%
    // interest rate = 10.2941176456512000% per year
    // 1 day passed _bobExpectedDebtAmount = debtAmount + (debtAmount * seconedPass * ratePerSec)
    // = 10 + (10 * 1 * 0.102941176456512000/365) ~ 10.002820, (precision loss 1)
    uint256 _bobExpectedDebtAmount = normalizeEther(10.002819 ether, usdcDecimal);
    assertEq(_bobActualDebtAmount, _bobExpectedDebtAmount);

    // assert ALICE
    (, uint256 _aliceActualDebtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, subAccount0, address(usdc));
    // _aliceExpectedDebtAmount should be 10 ether
    // so _aliceExpectedDebtAmount = 10 ether
    uint256 _aliceExpectedDebtAmount = normalizeEther(10 ether, usdcDecimal);
    assertEq(_aliceActualDebtAmount, _aliceExpectedDebtAmount, "Alice debtAmount missmatch");

    // assert Global
    // from BOB 10 + 0.002820 = 10.002820, Alice 10 = 20.002820
    assertEq(
      viewFacet.getOverCollatTokenDebtValue(address(usdc)),
      normalizeEther(20.002820 ether, usdcDecimal),
      "Global getOverCollatDebtValue missmatch"
    );

    // assert IB exchange rate change
    // alice wthdraw 10 ibUSDC, totalToken = 20.002820, totalSupply = 20
    // alice should get = 10 * 20.002820 / 20 = 10.00141 eth
    uint256 _expectdAmount = normalizeEther(10.001410 ether, usdcDecimal);
    _aliceBalanceBefore = usdc.balanceOf(ALICE);
    //can't withdraw because there's no reserve
    vm.expectRevert(abi.encodeWithSignature("LibMoneyMarket01_NotEnoughToken()"));
    vm.prank(ALICE);
    lendFacet.withdraw(ALICE, address(ibUsdc), _usdcBorrowAmount);

    // once there's lender, alice can now withdraw
    vm.prank(BOB);
    accountManager.deposit(address(usdc), _expectdAmount);
    vm.prank(ALICE);
    lendFacet.withdraw(ALICE, address(ibUsdc), _usdcBorrowAmount);

    _aliceBalanceAfter = usdc.balanceOf(ALICE);

    assertEq(_aliceBalanceAfter - _aliceBalanceBefore, _expectdAmount, "ALICE weth balance missmatch");
  }

  function testCorrectness_WhenUserBorrowBothOverCollatAndNonCollat_ShouldaccrueInterestCorrectly() external {
    uint256 _actualInterest = viewFacet.getGlobalPendingInterest(address(weth));
    assertEq(_actualInterest, 0);

    uint256 _wethBorrowAmount = 10 ether;
    uint256 _nonCollatBorrowAmount = 10 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethBorrowAmount * 2);

    uint256 _bobBalanceBefore = weth.balanceOf(BOB);
    // bob borrow
    borrowFacet.borrow(BOB, subAccount0, address(weth), _wethBorrowAmount);
    //bob non collat borrow
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _nonCollatBorrowAmount);
    vm.stopPrank();

    uint256 _bobBalanceAfter = weth.balanceOf(BOB);

    assertEq(_bobBalanceAfter - _bobBalanceBefore, _wethBorrowAmount + _nonCollatBorrowAmount);

    uint256 _debtAmount;
    (, _debtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(BOB, subAccount0, address(weth));
    uint256 _nonCollatDebtAmount = viewFacet.getNonCollatAccountDebt(BOB, address(weth));
    assertEq(_debtAmount, _wethBorrowAmount);
    assertEq(_nonCollatDebtAmount, _nonCollatBorrowAmount);

    vm.warp(block.timestamp + 10);

    uint256 _expectedDebtAmount = 2e18 + _wethBorrowAmount;
    uint256 _expectedNonDebtAmount = 2e18 + _nonCollatBorrowAmount;

    uint256 _actualInterestAfter = viewFacet.getGlobalPendingInterest(address(weth));
    assertEq(_actualInterestAfter, 4e18);
    borrowFacet.accrueInterest(address(weth));
    (, uint256 _actualDebtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(BOB, subAccount0, address(weth));
    assertEq(_actualDebtAmount, _expectedDebtAmount);
    uint256 _bobNonCollatDebt = viewFacet.getNonCollatAccountDebt(BOB, address(weth));
    uint256 _tokenCollatDebt = viewFacet.getNonCollatTokenDebt(address(weth));
    assertEq(_bobNonCollatDebt, _expectedNonDebtAmount);
    assertEq(_tokenCollatDebt, _expectedNonDebtAmount);

    uint256 _actualAccrueTime = viewFacet.getDebtLastAccruedAt(address(weth));
    assertEq(_actualAccrueTime, block.timestamp);
  }

  function testCorrectness_WhenAccrueInterestAndThereIsLendingFee_ProtocolShouldGetRevenue() external {
    // set lending fee to 100 bps
    adminFacet.setFees(100, 0, 0, 0);
    uint256 _actualInterest = viewFacet.getGlobalPendingInterest(address(weth));
    assertEq(_actualInterest, 0);

    uint256 _wethBorrowAmount = 10 ether;
    uint256 _nonCollatBorrowAmount = 10 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethBorrowAmount * 2);

    uint256 _bobBalanceBefore = weth.balanceOf(BOB);
    // bob borrow
    borrowFacet.borrow(BOB, subAccount0, address(weth), _wethBorrowAmount);
    //bob non collat borrow
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _nonCollatBorrowAmount);
    vm.stopPrank();

    uint256 _bobBalanceAfter = weth.balanceOf(BOB);

    assertEq(_bobBalanceAfter - _bobBalanceBefore, _wethBorrowAmount + _nonCollatBorrowAmount);

    uint256 _debtAmount;
    (, _debtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(BOB, subAccount0, address(weth));
    uint256 _nonCollatDebtAmount = viewFacet.getNonCollatAccountDebt(BOB, address(weth));
    assertEq(_debtAmount, _wethBorrowAmount);
    assertEq(_nonCollatDebtAmount, _nonCollatBorrowAmount);

    vm.warp(block.timestamp + 10);

    uint256 _expectedDebtAmount = 2e18 + _wethBorrowAmount;
    uint256 _expectedNonDebtAmount = 2e18 + _nonCollatBorrowAmount;

    uint256 _actualInterestAfter = viewFacet.getGlobalPendingInterest(address(weth));
    assertEq(_actualInterestAfter, 4e18);

    uint256 _totalTokenWithInterestBeforeAccrue = viewFacet.getTotalTokenWithPendingInterest(address(weth));
    borrowFacet.accrueInterest(address(weth));
    // total token with interest before accrue should equal to total token after accrue
    assertEq(_totalTokenWithInterestBeforeAccrue, viewFacet.getTotalToken(address(weth)));
    (, uint256 _actualDebtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(BOB, subAccount0, address(weth));
    assertEq(_actualDebtAmount, _expectedDebtAmount);
    uint256 _bobNonCollatDebt = viewFacet.getNonCollatAccountDebt(BOB, address(weth));
    uint256 _tokenCollatDebt = viewFacet.getNonCollatTokenDebt(address(weth));
    assertEq(_bobNonCollatDebt, _expectedNonDebtAmount);
    assertEq(_tokenCollatDebt, _expectedNonDebtAmount);

    uint256 _actualAccrueTime = viewFacet.getDebtLastAccruedAt(address(weth));
    assertEq(_actualAccrueTime, block.timestamp);

    // total token without lending fee = 54000000000000000000
    // 100 bps for lending fee on interest = (4e18 * 100 / 10000) = 4 e16
    // total token =  54 e18 - 4e16 = 5396e16
    assertEq(viewFacet.getTotalToken(address(weth)), 5396e16);
    assertEq(viewFacet.getProtocolReserve(address(weth)), 4e16);

    // test withdrawing reserve
    vm.expectRevert(IAdminFacet.AdminFacet_ReserveTooLow.selector);
    adminFacet.withdrawProtocolReserve(address(weth), address(this), 5e16);

    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.withdrawProtocolReserve(address(weth), address(this), 4e16);

    adminFacet.withdrawProtocolReserve(address(weth), address(this), 4e16);
    assertEq(viewFacet.getProtocolReserve(address(weth)), 0);
    assertEq(viewFacet.getTotalToken(address(weth)), 5396e16);
  }

  function testCorrectness_WhenUsersBorrowSameTokenButDifferentInterestModel_ShouldaccrueInterestCorrectly() external {
    uint256 _aliceBorrowAmount = 15 ether;
    uint256 _bobBorrowAmount = 15 ether;

    vm.prank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(btc), _aliceBorrowAmount * 2);

    vm.prank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(btc), _bobBorrowAmount * 2);

    uint256 _aliceBalanceBefore = btc.balanceOf(ALICE);
    uint256 _bobBalanceBefore = btc.balanceOf(BOB);

    vm.prank(ALICE);
    nonCollatBorrowFacet.nonCollatBorrow(address(btc), _aliceBorrowAmount);

    assertEq(btc.balanceOf(ALICE) - _aliceBalanceBefore, _aliceBorrowAmount);

    vm.prank(BOB);
    nonCollatBorrowFacet.nonCollatBorrow(address(btc), _bobBorrowAmount);

    assertEq(btc.balanceOf(BOB) - _bobBalanceBefore, _bobBorrowAmount);

    uint256 _secondPassed = 1 days;
    vm.warp(block.timestamp + _secondPassed);

    borrowFacet.accrueInterest(address(btc));

    // alice and bob both borrowed 15 on each, total is 30, pool has 100 btc, utilization = 30%
    // for alice has interest rate = 6.1764705867600000% per year
    // for bob has interest rate = 8.5714285713120000% per year
    // 1 day passed _bobExpectedDebtAmount = debtAmount + (debtAmount * seconedPass * ratePerSec)
    // alice = 15 + (15 * 1 * 0.061764705867600000/365) = 15.002538275583600000
    // bob = 15 + (15 * 1 * 0.085714285713120000/365) = 15.003522504892320000
    uint256 _aliceDebt = viewFacet.getNonCollatAccountDebt(ALICE, address(btc));
    assertEq(_aliceDebt, 15.002538275583600000 ether, "Alice debtAmount mismatch");
    uint256 _bobDebt = viewFacet.getNonCollatAccountDebt(BOB, address(btc));
    assertEq(_bobDebt, 15.003522504892320000 ether, "Bob debtAmount mismatch");

    // assert Global
    // from Alice 15.002538275583600000, Bob 15.003522504892320000 = 15.002538275583600000 + 15.003522504892320000 = 30.006060780475920000
    assertEq(
      viewFacet.getNonCollatTokenDebt(address(btc)),
      30.006060780475920000 ether,
      "Global getOverCollatDebtValue missmatch"
    );
  }

  function testCorrectness_WhenUserBorrowMultipleTokens_AllDebtTokenShouldAccrueInterest() external {
    vm.prank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(btc), 100 ether);

    // add 100 btc, collateralFactor = 9000, weth price = 10
    // _borrowingPowerUSDValue = 100 * 10 * 9000/ 10000 = 900 ether USD
    assertEq(viewFacet.getTotalBorrowingPower(ALICE, subAccount0), 900 ether);

    // borrow 9 weth => with 9000 borrow factor
    vm.prank(ALICE);
    borrowFacet.borrow(ALICE, subAccount0, address(weth), 9 ether);
    // weth debt share = 9, debt value = 9
    // borrowed value = 9 * 9 / 9 = 9
    // the used borrowed power should be 9 * 10000 / 9000 = 10 ether

    (uint256 _borrowedUSDValue, ) = viewFacet.getTotalUsedBorrowingPower(ALICE, subAccount0);
    assertEq(_borrowedUSDValue, 10 ether);

    // timepast 100
    vm.warp(block.timestamp + 100);
    // weth interest model = 0.009 ether per second
    // weth pending interest for 1 borrowed token should be 0.009 * 100 = 0.9 ether
    // alice has borrowed 9 ether then pendint interest will be 9 * 0.9 ether = 8.1 ether
    assertEq(viewFacet.getGlobalPendingInterest(address(weth)), 8.1 ether);

    // alice borrow other asset, weth debt value should be accrued interest
    // borrow 9 usdc => with 9000 borrow factor
    vm.prank(ALICE);
    borrowFacet.borrow(ALICE, subAccount0, address(usdc), normalizeEther(9 ether, usdcDecimal));

    // weth debt value increased by 8.1
    // weth debt share = 9, debt value = 9 + 8.1 = 17.1
    // borrowed value = 9 * 17.1 / 9 = 17.1
    // the used borrowed power (weth) should be 17.1 * 10000 / 9000 = 19 ether

    // usdc debt share = 9, debt value = 9
    // borrowed value = 9 * 9 / 9 = 9
    // the used borrowed power (usdc) should be 9 * 10000 / 9000 = 10 ether

    // total used borrowed power = 19 + 10 = 29 ether
    (_borrowedUSDValue, ) = viewFacet.getTotalUsedBorrowingPower(ALICE, subAccount0);
    assertEq(_borrowedUSDValue, 29 ether);
  }

  function testCorrectness_WhenUserNonCollatBorrowMultipleTokens_AllDebtTokenShouldAccrueInterest() external {
    // borrow 9 weth => with 9000 borrow factor
    vm.prank(ALICE);
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), 9 ether);
    // weth debt share = 9, debt value = 9
    // borrowed value = 9 * 9 / 9 = 9
    // the used borrowed power should be 9 * 10000 / 9000 = 10 ether

    uint256 _borrowedUSDValue = viewFacet.getTotalNonCollatUsedBorrowingPower(ALICE);
    assertEq(_borrowedUSDValue, 10 ether);

    // timepast 100
    vm.warp(block.timestamp + 100);
    // weth interest model = 0.009 ether per second
    // weth pending interest for 1 borrowed token should be 0.009 * 100 = 0.9 ether
    // alice has borrowed 9 ether then pendint interest will be 9 * 0.9 ether = 8.1 ether
    assertEq(viewFacet.getGlobalPendingInterest(address(weth)), 8.1 ether);

    // alice borrow other asset, weth debt value should be accrued interest
    // borrow 9 usdc => with 9000 borrow factor
    vm.prank(ALICE);
    nonCollatBorrowFacet.nonCollatBorrow(address(usdc), normalizeEther(9 ether, usdcDecimal));

    // weth debt value increased by 8.1
    // weth debt share = 9, debt value = 9 + 8.1 = 17.1
    // borrowed value = 9 * 17.1 / 9 = 17.1
    // the used borrowed power (weth) should be 17.1 * 10000 / 9000 = 19 ether

    // usdc debt share = 9, debt value = 9
    // borrowed value = 9 * 9 / 9 = 9
    // the used borrowed power (usdc) should be 9 * 10000 / 9000 = 10 ether

    // total used borrowed power = 19 + 10 = 29 ether
    _borrowedUSDValue = viewFacet.getTotalNonCollatUsedBorrowingPower(ALICE);
    assertEq(_borrowedUSDValue, 29 ether);
  }
}
