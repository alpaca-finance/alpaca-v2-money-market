// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, console } from "./MoneyMarket_BaseTest.t.sol";

// interfaces
import { IBorrowFacet, LibDoublyLinkedList } from "../../contracts/money-market/facets/BorrowFacet.sol";
import { IAdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";

import { FixedInterestRateModel } from "../../contracts/money-market/interest-models/FixedInterestRateModel.sol";

contract MoneyMarket_OverCollatBorrow_RepayWithCollatTest is MoneyMarket_BaseTest {
  MockERC20 mockToken;
  address _aliceSubaccount0;

  function setUp() public override {
    super.setUp();

    _aliceSubaccount0 = address(uint160(ALICE) ^ uint160(0));

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    // set interest to make sure that repay work correclty with share
    FixedInterestRateModel model = new FixedInterestRateModel();
    adminFacet.setInterestModel(address(weth), address(model));
    adminFacet.setInterestModel(address(usdc), address(model));

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

    vm.warp(block.timestamp + 10);
    // debt value should increase by 1 ether when accrue interest
    // before all alice weth debt share = 10 ether, debt value = 11 ether
  }

  function testCorrectness_WhenUserRepayWithCollat_DebtValueAndCollatShouldDecrease() external {
    uint256 _debtShare;
    uint256 _debtAmount;
    uint256 _globalDebtShare;
    uint256 _globalDebtValue;
    (uint256 _repayShareAmount, ) = viewFacet.getOverCollatSubAccountDebt(ALICE, subAccount0, address(weth));
    uint256 _collatBefore = viewFacet.getTotalCollat(address(weth));

    vm.prank(ALICE);
    // repay all debt share
    borrowFacet.repayWithCollat(subAccount0, address(weth), _repayShareAmount);

    (_debtShare, _debtAmount) = viewFacet.getOverCollatSubAccountDebt(ALICE, subAccount0, address(weth));
    (_globalDebtShare, _globalDebtValue) = viewFacet.getOverCollatTokenDebt(address(weth));
    assertEq(_debtShare, 0);
    assertEq(_debtAmount, 0);
    assertEq(_globalDebtShare, 0);
    assertEq(_globalDebtValue, 0);

    // repay share = 10
    // actual amount to repay = repayShare * debtValue / debtShare = 10 * 11 / 10 = 11 ether
    uint256 _expectedActualRepayAmount = 11 ether;
    assertEq(viewFacet.getTotalCollat(address(weth)), _collatBefore - _expectedActualRepayAmount);
  }

  function testCorrectness_WhenUserRepayWithCollatMoreThanExistingDebt_ShouldTransferOnlyAcutualRepayAmount() external {
    uint256 _debtShare;
    uint256 _debtAmount;
    uint256 _repayShare = 20 ether;
    uint256 _globalDebtShare;
    uint256 _globalDebtValue;
    (_debtShare, _debtAmount) = viewFacet.getOverCollatSubAccountDebt(ALICE, subAccount0, address(weth));
    uint256 _collatBefore = viewFacet.getTotalCollat(address(weth));

    uint256 _wethBalanceBefore = weth.balanceOf(ALICE);
    uint256 _totalTokenBefore = viewFacet.getTotalToken(address(weth));
    vm.prank(ALICE);
    borrowFacet.repayWithCollat(subAccount0, address(weth), _repayShare);
    uint256 _wethBalanceAfter = weth.balanceOf(ALICE);
    uint256 _totalTokenAfter = viewFacet.getTotalToken(address(weth));

    (_debtShare, _debtAmount) = viewFacet.getOverCollatSubAccountDebt(ALICE, subAccount0, address(weth));
    (_globalDebtShare, _globalDebtValue) = viewFacet.getOverCollatTokenDebt(address(weth));

    // expect facet should not exchange token with sender
    assertEq(_wethBalanceBefore - _wethBalanceAfter, 0 ether);
    assertEq(_totalTokenAfter, _totalTokenBefore + 1 ether); // 1 ether is come from interest
    assertEq(_debtAmount, 0);
    assertEq(_globalDebtShare, 0);
    assertEq(_globalDebtValue, 0);

    // repay share = 10
    // actual amount to repay = repayShare * debtValue / debtShare = 10 * 11 / 10 = 11 ether
    uint256 _expectedActualRepayAmount = 11 ether;
    assertEq(viewFacet.getTotalCollat(address(weth)), _collatBefore - _expectedActualRepayAmount);
  }

  function testCorrectness_WhenUserRepayWithCollatWithTinyAmount_ShouldWork() external {
    uint256 _debtShare;
    uint256 _debtAmount;
    uint256 _repayShareAmount = 5 ether;
    uint256 _globalDebtShare;
    uint256 _globalDebtValue;
    (_debtShare, _debtAmount) = viewFacet.getOverCollatSubAccountDebt(ALICE, subAccount0, address(weth));
    uint256 _collatBefore = viewFacet.getTotalCollat(address(weth));

    uint256 _wethBalanceBefore = weth.balanceOf(ALICE);
    vm.prank(ALICE);
    borrowFacet.repayWithCollat(subAccount0, address(weth), _repayShareAmount);
    uint256 _wethBalanceAfter = weth.balanceOf(ALICE);

    (_debtShare, _debtAmount) = viewFacet.getOverCollatSubAccountDebt(ALICE, subAccount0, address(weth));
    (_globalDebtShare, _globalDebtValue) = viewFacet.getOverCollatTokenDebt(address(weth));

    // expect facet should not exchange token with sender
    assertEq(_wethBalanceBefore - _wethBalanceAfter, 0 ether);
    assertEq(_debtShare, 5 ether);
    assertEq(_debtAmount, 5.5 ether);
    assertEq(_globalDebtShare, 5 ether);
    assertEq(_globalDebtValue, 5.5 ether);

    // repay share = 10
    // actual amount to repay = repayShare * debtValue / debtShare = 5 * 11 / 10 = 5.5 ether
    uint256 _expectedActualRepayAmount = 5.5 ether;
    assertEq(viewFacet.getTotalCollat(address(weth)), _collatBefore - _expectedActualRepayAmount);
  }

  function testCorrectness_WhenUserRepayWithCollatAndDebtIsMoreThanCollatAmount_ShoulRepayOnlyAsCollatAmount()
    external
  {
    uint256 _debtShare;
    uint256 _debtAmount;
    uint256 _globalDebtShare;
    uint256 _globalDebtValue;
    // set up for case collat is less than debt
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(usdc), 5 ether);
    borrowFacet.borrow(subAccount0, address(usdc), 10 ether);
    vm.stopPrank();

    vm.warp(block.timestamp + 10);
    // usdc debt value should increase by 1 ether

    (_debtShare, _debtAmount) = viewFacet.getOverCollatSubAccountDebt(ALICE, subAccount0, address(usdc));

    vm.prank(ALICE);
    // debt share = 10, debt value = 11
    borrowFacet.repayWithCollat(subAccount0, address(usdc), 10 ether);

    // due to alice provide only 5 ether for collat on USDC but borrow 10 ether
    // alice repay with collat as 10 ether, the result should be repay only 5 ether follow collat amount
    // then collat as share is 5 * 10 / 11 = 4.545454545454545454
    // actual repay share = Min(repayShare, debtShare, collatAsShare) = Min(10, 10, 4.545454545454545454)
    // then actual repay share = 4.545454545454545454
    (_debtShare, _debtAmount) = viewFacet.getOverCollatSubAccountDebt(ALICE, subAccount0, address(usdc));
    (_globalDebtShare, _globalDebtValue) = viewFacet.getOverCollatTokenDebt(address(usdc));

    // repay share = 4.545454545454545454
    // actual amount to repay = repayShare * debtValue / debtShare = 4.545454545454545454 * 11 / 10 = 4.999999999999999999 ether
    uint256 _actualRepayShare = 4.545454545454545454 ether;
    uint256 _actualRepayAmount = 4.999999999999999999 ether;
    assertEq(_debtShare, 10 ether - _actualRepayShare);
    assertEq(_debtAmount, 11 ether - _actualRepayAmount);
    assertEq(_globalDebtShare, 10 ether - _actualRepayShare);
    assertEq(_globalDebtValue, 11 ether - _actualRepayAmount);

    assertEq(viewFacet.getTotalCollat(address(usdc)), 1); // dust
  }

  function testRevert_WhenUserRepayWithCollatAndTokenDebtGoesLowerThanMinimumDebtSize() external {
    // ALICE borrow for 10 ether in setUp
    // minDebtSize = 0.1 ether, set in mm base test
    // 1 weth = 1 ibWeth

    vm.startPrank(ALICE);

    // debt - repay < minDebtSize should revert
    // 10 - 9.99 < 0.1
    vm.expectRevert(IBorrowFacet.BorrowFacet_BorrowLessThanMinDebtSize.selector);
    borrowFacet.repayWithCollat(subAccount0, address(weth), 9.99 ether);

    // totalBorrowingPowerAfterRepay > minDebtSize should not revert
    // 10 - 0.01 > 0.1
    borrowFacet.repayWithCollat(subAccount0, address(weth), 0.01 ether);

    // weth debt remaining = 9.99
    // totalBorrowingPowerAfterRepay == minDebtSize should not revert
    // 9.99 - 9.89 == 0.1
    borrowFacet.repayWithCollat(subAccount0, address(weth), 9.89 ether);

    // weth debt remaining = 0.1
    // repay entire debt should not revert
    borrowFacet.repayWithCollat(subAccount0, address(weth), 0.1 ether);

    (, uint256 _debtAmount) = viewFacet.getOverCollatSubAccountDebt(ALICE, subAccount0, address(weth));
    assertEq(_debtAmount, 0);
  }
}
