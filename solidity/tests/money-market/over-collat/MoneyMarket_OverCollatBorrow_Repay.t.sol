// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest, MockERC20, DebtToken, console } from "../MoneyMarket_BaseTest.t.sol";

// interfaces
import { IMoneyMarketAccountManager } from "../../../contracts/interfaces/IMoneyMarketAccountManager.sol";
import { IBorrowFacet } from "../../../contracts/money-market/interfaces/IBorrowFacet.sol";
import { IAdminFacet } from "../../../contracts/money-market/interfaces/IAdminFacet.sol";
import { IMiniFL } from "../../../contracts/money-market/interfaces/IMiniFL.sol";

import { FixedInterestRateModel } from "../../../contracts/money-market/interest-models/FixedInterestRateModel.sol";

contract MoneyMarket_OverCollatBorrow_RepayTest is MoneyMarket_BaseTest {
  MockERC20 mockToken;
  IMiniFL _miniFL;

  function setUp() public override {
    super.setUp();

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    _miniFL = IMiniFL(address(miniFL));

    // set interest to make sure that repay work correclty with share
    FixedInterestRateModel wethModel = new FixedInterestRateModel(wethDecimal);
    FixedInterestRateModel wNativeModel = new FixedInterestRateModel(wNativeTokenDecimal);
    adminFacet.setInterestModel(address(weth), address(wethModel));
    adminFacet.setInterestModel(address(wNativeToken), address(wNativeModel));

    vm.startPrank(ALICE);
    accountManager.deposit(address(weth), normalizeEther(40 ether, wethDecimal));
    accountManager.deposit(address(usdc), normalizeEther(40 ether, usdcDecimal));
    accountManager.deposit(address(isolateToken), normalizeEther(40 ether, isolateTokenDecimal));
    accountManager.depositETH{ value: 40 ether }();
    vm.stopPrank();

    uint256 _aliceBorrowAmount = 10 ether;
    mockOracle.setTokenPrice(address(wNativeToken), 1 ether);

    // set up borrow first
    vm.startPrank(ALICE);
    accountManager.addCollateralFor(ALICE, subAccount0, address(weth), 100 ether);
    accountManager.borrow(subAccount0, address(weth), _aliceBorrowAmount);
    accountManager.borrowETH(subAccount0, _aliceBorrowAmount);
    vm.stopPrank();

    vm.warp(block.timestamp + 10);
    // debt value should increase by 1 ether when accrue interest
    // before all alice weth debt share = 10 ether, debt value = 11 ether
  }

  function testCorrectness_WhenUserRepayDebt_DebtValueShouldDecrease() external {
    uint256 _debtShare;
    uint256 _debtAmount;
    uint256 _globalDebtShare;
    uint256 _globalDebtValue;
    (_debtShare, _debtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, subAccount0, address(weth));

    // get debt token balance before repay
    address _debtToken = viewFacet.getDebtTokenFromToken(address(weth));
    uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(_debtToken);

    uint256 _debtTokenBalanceBefore = _miniFL.getUserTotalAmountOf(_poolId, ALICE);
    uint256 _debtShareBefore = _debtShare;
    assertEq(_debtTokenBalanceBefore, _debtShareBefore);

    vm.prank(ALICE);
    // repay all debt share
    accountManager.repayFor(ALICE, subAccount0, address(weth), 100 ether, _debtShare);

    (_debtShare, _debtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, subAccount0, address(weth));
    (_globalDebtShare, _globalDebtValue) = viewFacet.getOverCollatTokenDebt(address(weth));
    assertEq(_debtShare, 0);
    assertEq(_debtAmount, 0);
    assertEq(_globalDebtShare, 0);
    assertEq(_globalDebtValue, 0);

    // debt token in MiniFL should be zero (withdrawn & burned)
    // since debt token is minted only one time, so the totalSupply should be equal to _debtTokenBalanceAfter after burned
    uint256 _debtTokenBalanceAfter = _miniFL.getUserTotalAmountOf(_poolId, ALICE);
    assertEq(_debtTokenBalanceAfter, _debtTokenBalanceBefore - _debtShareBefore);
    assertEq(DebtToken(_debtToken).totalSupply(), _debtTokenBalanceAfter);
  }

  function testCorrectness_WhenUserRepayDebtWithNativeToken_DebtValueShouldDecrease() external {
    uint256 _debtShare;
    uint256 _debtAmount;
    uint256 _globalDebtShare;
    uint256 _globalDebtValue;
    (_debtShare, _debtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, subAccount0, address(wNativeToken));

    // get debt token balance before repay
    address _debtToken = viewFacet.getDebtTokenFromToken(address(wNativeToken));
    uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(_debtToken);

    uint256 _debtTokenBalanceBefore = _miniFL.getUserTotalAmountOf(_poolId, ALICE);
    uint256 _debtShareBefore = _debtShare;
    assertEq(_debtTokenBalanceBefore, _debtShareBefore);

    vm.prank(ALICE);
    // repay all debt share
    accountManager.repayETHFor{ value: 100 ether }(ALICE, subAccount0, _debtShare);

    (_debtShare, _debtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, subAccount0, address(wNativeToken));
    (_globalDebtShare, _globalDebtValue) = viewFacet.getOverCollatTokenDebt(address(wNativeToken));
    assertEq(_debtShare, 0);
    assertEq(_debtAmount, 0);
    assertEq(_globalDebtShare, 0);
    assertEq(_globalDebtValue, 0);

    // debt token in MiniFL should be zero (withdrawn & burned)
    // since debt token is minted only one time, so the totalSupply should be equal to _debtTokenBalanceAfter after burned
    uint256 _debtTokenBalanceAfter = _miniFL.getUserTotalAmountOf(_poolId, ALICE);
    assertEq(_debtTokenBalanceAfter, _debtTokenBalanceBefore - _debtShareBefore);
    assertEq(DebtToken(_debtToken).totalSupply(), _debtTokenBalanceAfter);
  }

  function testCorrectness_WhenUserRepayDebtAfterTimepass_DebtTokenInMiniFLShouldBeRemovedCorrectly() external {
    // get debt token balance before repay
    address _debtToken = viewFacet.getDebtTokenFromToken(address(weth));
    uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(_debtToken);
    (, uint256 _debtAmountBefore) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, subAccount0, address(weth));

    // _pendingInterest = 1 ether, after accrue interest, the debt amount should be increased by 1 ether
    uint256 _pendingInterest = viewFacet.getGlobalPendingInterest(address(weth));
    borrowFacet.accrueInterest(address(weth));

    (, uint256 _debtAmountAfterAccrue) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, subAccount0, address(weth));
    assertEq(_debtAmountAfterAccrue, _debtAmountBefore + _pendingInterest);

    // now if alice borrow more 11 ether, the debt share should be increased by 10 ether
    // since _debtShareAfterAccrue: 11 ether, while _debtAmountAfterAccrue: 10 ether
    vm.startPrank(ALICE);
    uint256 _aliceSecondBorrowAmount = _debtAmountBefore + _pendingInterest;
    accountManager.borrow(subAccount0, address(weth), _aliceSecondBorrowAmount);
    (uint256 _debtShareAfterSecondBorrow, uint256 _debtAmountAfterSecondBorrow) = viewFacet
      .getOverCollatDebtShareAndAmountOf(ALICE, subAccount0, address(weth));

    // after repay with all debt share, the debt share and debt token (in MiniFL) should be zero
    accountManager.repayFor(
      ALICE,
      subAccount0,
      address(weth),
      _debtAmountAfterSecondBorrow,
      _debtShareAfterSecondBorrow
    );
    assertEq(_miniFL.getUserTotalAmountOf(_poolId, ALICE), 0);
    assertEq(DebtToken(_debtToken).totalSupply(), 0);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserRepayDebtMoreThanExistingDebt_ShouldTransferOnlyAcutualRepayAmount() external {
    uint256 _debtAmount;
    uint256 _debtShare;
    uint256 _repayShare = 20 ether;
    uint256 _globalDebtShare;
    uint256 _globalDebtValue;
    (_debtShare, _debtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, subAccount0, address(weth));

    uint256 _wethBalanceBefore = weth.balanceOf(ALICE);
    uint256 _totalTokenBefore = viewFacet.getTotalToken(address(weth));
    vm.prank(ALICE);
    accountManager.repayFor(ALICE, subAccount0, address(weth), 20 ether, _repayShare);
    uint256 _wethBalanceAfter = weth.balanceOf(ALICE);
    uint256 _totalTokenAfter = viewFacet.getTotalToken(address(weth));

    (_debtShare, _debtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, subAccount0, address(weth));
    (_globalDebtShare, _globalDebtValue) = viewFacet.getOverCollatTokenDebt(address(weth));

    // repay share = 10
    // actual amount to repay = repayShare * debtValue / debtShare = 10 * 11 / 10 = 11 ether
    uint256 _expectedActualRepayAmount = 11 ether;
    assertEq(_wethBalanceBefore - _wethBalanceAfter, _expectedActualRepayAmount);
    assertEq(_totalTokenAfter, _totalTokenBefore + 1 ether); // 1 ether is come from interest
    assertEq(_debtShare, 0);
    assertEq(_debtAmount, 0);
    assertEq(_globalDebtShare, 0);
    assertEq(_globalDebtValue, 0);
  }

  function testCorrectness_WhenUserRepayDebtWithNativeTokenMoreThanExistingDebt_ShouldTransferOnlyAcutualRepayAmount()
    external
  {
    uint256 _debtAmount;
    uint256 _debtShare;
    uint256 _repayShare = 20 ether;
    uint256 _globalDebtShare;
    uint256 _globalDebtValue;
    (_debtShare, _debtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, subAccount0, address(wNativeToken));

    uint256 _balanceBefore = ALICE.balance;
    uint256 _totalTokenBefore = viewFacet.getTotalToken(address(wNativeToken));
    vm.prank(ALICE);
    accountManager.repayETHFor{ value: 20 ether }(ALICE, subAccount0, _repayShare);
    uint256 _balanceAfter = ALICE.balance;
    uint256 _totalTokenAfter = viewFacet.getTotalToken(address(wNativeToken));

    (_debtShare, _debtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, subAccount0, address(wNativeToken));
    (_globalDebtShare, _globalDebtValue) = viewFacet.getOverCollatTokenDebt(address(wNativeToken));

    // repay share = 10
    // actual amount to repay = repayShare * debtValue / debtShare = 10 * 11 / 10 = 11 ether
    uint256 _expectedActualRepayAmount = 11 ether;
    assertEq(_balanceBefore - _balanceAfter, _expectedActualRepayAmount);
    assertEq(_totalTokenAfter, _totalTokenBefore + 1 ether); // 1 ether is come from interest
    assertEq(_debtShare, 0);
    assertEq(_debtAmount, 0);
    assertEq(_globalDebtShare, 0);
    assertEq(_globalDebtValue, 0);
  }

  function testCorrectness_WhenUserRepayWithTinyAmount_ShouldWork() external {
    uint256 _debtShare;
    uint256 _debtAmount;
    uint256 _repayShare = 5 ether;
    uint256 _globalDebtShare;
    uint256 _globalDebtValue;
    (_debtShare, _debtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, subAccount0, address(weth));

    // get debt token balance before repay
    address _debtToken = viewFacet.getDebtTokenFromToken(address(weth));
    uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(_debtToken);

    uint256 _debtTokenBalanceBefore = _miniFL.getUserTotalAmountOf(_poolId, ALICE);
    assertEq(_debtTokenBalanceBefore, _debtShare);

    uint256 _wethBalanceBefore = weth.balanceOf(ALICE);
    vm.prank(ALICE);
    accountManager.repayFor(ALICE, subAccount0, address(weth), 5.5 ether, _repayShare);
    uint256 _wethBalanceAfter = weth.balanceOf(ALICE);

    (_debtShare, _debtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, subAccount0, address(weth));
    (_globalDebtShare, _globalDebtValue) = viewFacet.getOverCollatTokenDebt(address(weth));

    // repay share = 5
    // actual amount to repay = repayShare * debtValue / debtShare = 5 * 11 / 10 = 5.5 ether
    uint256 _expectedActualRepayAmount = 5.5 ether;
    assertEq(_wethBalanceBefore - _wethBalanceAfter, _expectedActualRepayAmount);
    assertEq(_debtShare, 5 ether);
    assertEq(_debtAmount, 5.5 ether);
    assertEq(_globalDebtShare, 5 ether);
    assertEq(_globalDebtValue, 5.5 ether);

    // debt token in MiniFL should be equal to _debtTokenBalanceBefore - _repayShare (withdrawn & burned)
    // since debt token is minted only one time, so the totalSupply should be equal to _debtTokenBalanceAfter after burned
    uint256 _debtTokenBalanceAfter = _miniFL.getUserTotalAmountOf(_poolId, ALICE);
    assertEq(_debtTokenBalanceAfter, _debtTokenBalanceBefore - _repayShare);
    assertEq(DebtToken(_debtToken).totalSupply(), _debtTokenBalanceAfter);
  }

  function testRevert_WhenUserRepayAndTotalUsedBorrowingPowerAfterRepayIsLowerThanMinimum() external {
    // ALICE borrow for 10 ether in setUp
    // minDebtSize = 0.1 ether, set in mm base test

    vm.startPrank(ALICE);

    // totalBorrowingPowerAfterRepay < minDebtSize should revert
    vm.expectRevert(IBorrowFacet.BorrowFacet_BorrowLessThanMinDebtSize.selector);
    accountManager.repayFor(ALICE, subAccount0, address(weth), 20 ether, 9.99 ether);

    // totalBorrowingPowerAfterRepay > minDebtSize should not revert
    accountManager.repayFor(ALICE, subAccount0, address(weth), 20 ether, 0.01 ether);

    // weth debt remaining = 9.99
    // totalBorrowingPowerAfterRepay == minDebtSize should not revert
    accountManager.repayFor(ALICE, subAccount0, address(weth), 20 ether, 9.89 ether);

    // weth debt remaining = 0.1
    // repay entire debt should not revert
    accountManager.repayFor(ALICE, subAccount0, address(weth), 20 ether, 0.1 ether);

    vm.stopPrank();

    (, uint256 _debtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, subAccount0, address(weth));
    assertEq(_debtAmount, 0);
  }

  function testRevert_WhenUserRepayWithZeroAmountOrZeroDebtShareToRepay() external {
    vm.startPrank(ALICE);
    // repay amount = 0 should revert
    vm.expectRevert(IMoneyMarketAccountManager.MoneyMarketAccountManager_InvalidAmount.selector);
    accountManager.repayFor(ALICE, subAccount0, address(weth), 0, 1 ether);

    // repay debt share = 0 should revert
    vm.expectRevert(IMoneyMarketAccountManager.MoneyMarketAccountManager_InvalidAmount.selector);
    accountManager.repayFor(ALICE, subAccount0, address(weth), 1 ether, 0);

    // combine both should revert
    vm.expectRevert(IMoneyMarketAccountManager.MoneyMarketAccountManager_InvalidAmount.selector);
    accountManager.repayFor(ALICE, subAccount0, address(weth), 0, 0);
    vm.stopPrank();
  }

  function testRevert_WhenUserRepayNativeTokenWithZeroAmountOrZeroDebtShareToRepay() external {
    vm.startPrank(ALICE);
    // repay amount = 0 should revert
    vm.expectRevert(IMoneyMarketAccountManager.MoneyMarketAccountManager_InvalidAmount.selector);
    accountManager.repayETHFor{ value: 0 }(ALICE, subAccount0, 1 ether);

    // repay debt share = 0 should revert
    vm.expectRevert(IMoneyMarketAccountManager.MoneyMarketAccountManager_InvalidAmount.selector);
    accountManager.repayETHFor{ value: 1 ether }(ALICE, subAccount0, 0);

    // combine both should revert
    vm.expectRevert(IMoneyMarketAccountManager.MoneyMarketAccountManager_InvalidAmount.selector);
    accountManager.repayETHFor{ value: 0 }(ALICE, subAccount0, 0);
    vm.stopPrank();
  }

  function testRevert_WhenUserRepayDebtButNoDebtToRepay() external {
    // ALICE never borrow BTC
    // so there is no debt for BTC
    (uint256 _debtShare, uint256 _debtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(
      ALICE,
      subAccount0,
      address(btc)
    );
    assertEq(_debtShare, 0);
    assertEq(_debtAmount, 0);

    vm.prank(ALICE);
    vm.expectRevert(IBorrowFacet.BorrowFacet_NoDebtToRepay.selector);
    accountManager.repayFor(ALICE, subAccount0, address(btc), 20 ether, 10 ether);
  }
}
