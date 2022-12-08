// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, console } from "./MoneyMarket_BaseTest.t.sol";

// interfaces
import { IBorrowFacet, LibDoublyLinkedList } from "../../contracts/money-market/facets/BorrowFacet.sol";
import { IAdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";

contract MoneyMarket_RepayTest is MoneyMarket_BaseTest {
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

    uint256 _aliceBorrowAmount = 10 ether;

    // set up borrow first
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 100 ether);
    borrowFacet.borrow(subAccount0, address(weth), _aliceBorrowAmount);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserRepayDebt_DebtValueShouldDecrease() external {
    uint256 _debtAmount;
    uint256 _globalDebtShare;
    uint256 _globalDebtValue;
    (, _debtAmount) = borrowFacet.getDebt(ALICE, subAccount0, address(weth));

    vm.prank(ALICE);
    borrowFacet.repay(ALICE, subAccount0, address(weth), _debtAmount);

    (, _debtAmount) = borrowFacet.getDebt(ALICE, subAccount0, address(weth));
    (_globalDebtShare, _globalDebtValue) = borrowFacet.getGlobalDebt(address(weth));
    assertEq(_debtAmount, 0);
    assertEq(_globalDebtShare, 0);
    assertEq(_globalDebtValue, 0);

    assertEq(borrowFacet.accountDebtShares(ALICE, address(weth)), 0);
  }

  function testCorrectness_WhenUserRepayDebtMoreThanExistingDebt_ShouldTransferOnlyAcutualRepayAmount() external {
    uint256 _debtAmount;
    uint256 _repayAmount = 20 ether;
    uint256 _globalDebtShare;
    uint256 _globalDebtValue;
    (, _debtAmount) = borrowFacet.getDebt(ALICE, subAccount0, address(weth));

    uint256 _wethBalanceBefore = weth.balanceOf(ALICE);
    uint256 _totalTokenBefore = lendFacet.getTotalToken(address(weth));
    vm.prank(ALICE);
    borrowFacet.repay(ALICE, subAccount0, address(weth), _repayAmount);
    uint256 _wethBalanceAfter = weth.balanceOf(ALICE);
    uint256 _totalTokenAfter = lendFacet.getTotalToken(address(weth));

    (, _debtAmount) = borrowFacet.getDebt(ALICE, subAccount0, address(weth));
    (_globalDebtShare, _globalDebtValue) = borrowFacet.getGlobalDebt(address(weth));

    uint256 _expectedActualRepayAmount = 10 ether;
    assertEq(_wethBalanceBefore - _wethBalanceAfter, _expectedActualRepayAmount);
    assertEq(_totalTokenAfter, _totalTokenBefore);
    assertEq(_debtAmount, 0);
    assertEq(_globalDebtShare, 0);
    assertEq(_globalDebtValue, 0);
    assertEq(borrowFacet.accountDebtShares(ALICE, address(weth)), 0);
  }

  function testCorrectness_WhenUserRepayWithTinyAmount_ShouldWork() external {
    uint256 _debtAmount;
    uint256 _repayAmount = 5 ether;
    uint256 _globalDebtShare;
    uint256 _globalDebtValue;
    (, _debtAmount) = borrowFacet.getDebt(ALICE, subAccount0, address(weth));

    uint256 _wethBalanceBefore = weth.balanceOf(ALICE);
    vm.prank(ALICE);
    borrowFacet.repay(ALICE, subAccount0, address(weth), _repayAmount);
    uint256 _wethBalanceAfter = weth.balanceOf(ALICE);

    (, _debtAmount) = borrowFacet.getDebt(ALICE, subAccount0, address(weth));
    (_globalDebtShare, _globalDebtValue) = borrowFacet.getGlobalDebt(address(weth));

    assertEq(_wethBalanceBefore - _wethBalanceAfter, _repayAmount);
    assertEq(_debtAmount, 5 ether);
    assertEq(_globalDebtShare, 5 ether);
    assertEq(_globalDebtValue, 5 ether);
    assertEq(borrowFacet.accountDebtShares(ALICE, address(weth)), 5 ether);
  }

  function testCorrectness_WhenUserRepayWithCollat_DebtValueAndCollatShouldDecrease() external {
    uint256 _debtAmount;
    uint256 _globalDebtShare;
    uint256 _globalDebtValue;
    (, _debtAmount) = borrowFacet.getDebt(ALICE, subAccount0, address(weth));

    vm.prank(ALICE);
    borrowFacet.repayWithCollat(ALICE, subAccount0, address(weth), _debtAmount);

    (, _debtAmount) = borrowFacet.getDebt(ALICE, subAccount0, address(weth));
    (_globalDebtShare, _globalDebtValue) = borrowFacet.getGlobalDebt(address(weth));
    assertEq(_debtAmount, 0);
    assertEq(_globalDebtShare, 0);
    assertEq(_globalDebtValue, 0);
    assertEq(borrowFacet.accountDebtShares(ALICE, address(weth)), 0);

    assertEq(collateralFacet.collats(address(weth)), 90 ether);
  }

  function testCorrectness_WhenUserRepayWithIbCollat_DebtValueAndCollatShouldDecrease() external {
    uint256 _debtAmount;
    uint256 _globalDebtShare;
    uint256 _globalDebtValue;
    (, _debtAmount) = borrowFacet.getDebt(ALICE, subAccount0, address(weth));
    vm.startPrank(ALICE);

    weth.approve(moneyMarketDiamond, 10 ether);
    lendFacet.deposit(address(weth), 10 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, address(ibWeth), 10 ether);
    assertEq(collateralFacet.collats(address(ibWeth)), 10 ether);

    borrowFacet.repayWithIbCollat(ALICE, subAccount0, address(ibWeth), 5 ether);
    vm.stopPrank();

    (, _debtAmount) = borrowFacet.getDebt(ALICE, subAccount0, address(weth));
    (_globalDebtShare, _globalDebtValue) = borrowFacet.getGlobalDebt(address(weth));
    assertEq(_debtAmount, 5 ether);
    assertEq(_globalDebtShare, 5 ether);
    assertEq(_globalDebtValue, 5 ether);
    assertEq(borrowFacet.accountDebtShares(ALICE, address(weth)), 5 ether);

    assertEq(collateralFacet.collats(address(weth)), 100 ether);
    assertEq(collateralFacet.collats(address(ibWeth)), 5 ether);
  }

  function testCorrectness_WhenUserRepayWithCollatMoreThanExistingDebt_ShouldTransferOnlyAcutualRepayAmount() external {
    uint256 _debtAmount;
    uint256 _repayAmount = 20 ether;
    uint256 _globalDebtShare;
    uint256 _globalDebtValue;
    (, _debtAmount) = borrowFacet.getDebt(ALICE, subAccount0, address(weth));

    uint256 _wethBalanceBefore = weth.balanceOf(ALICE);
    uint256 _totalTokenBefore = lendFacet.getTotalToken(address(weth));
    vm.prank(ALICE);
    borrowFacet.repayWithCollat(ALICE, subAccount0, address(weth), _repayAmount);
    uint256 _wethBalanceAfter = weth.balanceOf(ALICE);
    uint256 _totalTokenAfter = lendFacet.getTotalToken(address(weth));

    (, _debtAmount) = borrowFacet.getDebt(ALICE, subAccount0, address(weth));
    (_globalDebtShare, _globalDebtValue) = borrowFacet.getGlobalDebt(address(weth));

    // expect facet should not exchange token with sender
    assertEq(_wethBalanceBefore - _wethBalanceAfter, 0 ether);
    assertEq(_totalTokenAfter, _totalTokenBefore);
    assertEq(_debtAmount, 0);
    assertEq(_globalDebtShare, 0);
    assertEq(_globalDebtValue, 0);
    assertEq(borrowFacet.accountDebtShares(ALICE, address(weth)), 0);

    assertEq(collateralFacet.collats(address(weth)), 90 ether);
  }

  function testCorrectness_WhenUserRepayWithCollatWithTinyAmount_ShouldWork() external {
    uint256 _debtAmount;
    uint256 _repayAmount = 5 ether;
    uint256 _globalDebtShare;
    uint256 _globalDebtValue;
    (, _debtAmount) = borrowFacet.getDebt(ALICE, subAccount0, address(weth));

    uint256 _wethBalanceBefore = weth.balanceOf(ALICE);
    vm.prank(ALICE);
    borrowFacet.repayWithCollat(ALICE, subAccount0, address(weth), _repayAmount);
    uint256 _wethBalanceAfter = weth.balanceOf(ALICE);

    (, _debtAmount) = borrowFacet.getDebt(ALICE, subAccount0, address(weth));
    (_globalDebtShare, _globalDebtValue) = borrowFacet.getGlobalDebt(address(weth));

    // expect facet should not exchange token with sender
    assertEq(_wethBalanceBefore - _wethBalanceAfter, 0 ether);
    assertEq(_debtAmount, 5 ether);
    assertEq(_globalDebtShare, 5 ether);
    assertEq(_globalDebtValue, 5 ether);
    assertEq(borrowFacet.accountDebtShares(ALICE, address(weth)), 5 ether);

    assertEq(collateralFacet.collats(address(weth)), 95 ether);
  }

  function testCorrectness_WhenUserRepayWithCollatAndDebtIsMoreThanCollatAmount_ShoulRepayOnlyAsCollatAmount()
    external
  {
    uint256 _debtAmount;
    uint256 _globalDebtShare;
    uint256 _globalDebtValue;
    // set up for case collat is less than debt
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(usdc), 5 ether);
    borrowFacet.borrow(subAccount0, address(usdc), 10 ether);
    vm.stopPrank();

    (, _debtAmount) = borrowFacet.getDebt(ALICE, subAccount0, address(usdc));

    vm.prank(ALICE);
    borrowFacet.repayWithCollat(ALICE, subAccount0, address(usdc), 10 ether);

    // due to alice provide only 5 ether for collat on USDC but borrow 10 ehter
    // alice repay with collat as 10 ether, the result should be repay only 5 ether follow collat amount
    (, _debtAmount) = borrowFacet.getDebt(ALICE, subAccount0, address(usdc));
    (_globalDebtShare, _globalDebtValue) = borrowFacet.getGlobalDebt(address(usdc));
    assertEq(_debtAmount, 5 ether);
    assertEq(_globalDebtShare, 5 ether);
    assertEq(_globalDebtValue, 5 ether);
    assertEq(borrowFacet.accountDebtShares(ALICE, address(usdc)), 5 ether);

    assertEq(collateralFacet.collats(address(usdc)), 0 ether);
  }
}
