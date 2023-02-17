// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest } from "../MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { IERC20 } from "../../../contracts/money-market/interfaces/IERC20.sol";
import { FixedInterestRateModel, IInterestRateModel } from "../../../contracts/money-market/interest-models/FixedInterestRateModel.sol";

contract MoneyMarket_AccountManagerTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_depositAndAddCollateral_ShouldWork() external {
    vm.prank(ALICE);
    accountManager.depositAndAddCollateral(0, address(weth), 10 ether);
  }

  function testCorrectness_depositETHTokenAndAddCollateral_ShouldWork() external {
    vm.prank(ALICE);
    accountManager.depositETHAndAddCollateral{ value: 10 ether }(0);
  }

  function testCorrectness_RemoveCollatAndWithdraw_ShouldWork() external {
    uint256 _wethBalanceBefore = weth.balanceOf(ALICE);
    vm.startPrank(ALICE);
    accountManager.depositAndAddCollateral(0, address(weth), 10 ether);
    accountManager.removeCollateralAndWithdraw(0, address(ibWeth), 10 ether);
    vm.stopPrank();

    assertEq(weth.balanceOf(ALICE), _wethBalanceBefore);
  }

  function testCorrectness_RemoveCollatAndWithdrawETH_ShouldWork() external {
    uint256 _nativeBalanceBefore = ALICE.balance;
    vm.startPrank(ALICE);
    accountManager.depositETHAndAddCollateral{ value: 10 ether }(0);
    accountManager.removeCollateralAndWithdrawETH(0, 10 ether);
    vm.stopPrank();

    assertEq(ALICE.balance, _nativeBalanceBefore);
  }

  function testCorrectness_UnstakeAndWithdraw_ShouldWork() external {
    uint256 _wethBalanceBefore = weth.balanceOf(ALICE);
    vm.startPrank(ALICE);
    accountManager.depositAndStake(address(weth), 10 ether);
    accountManager.unstakeAndWithdraw(address(ibWeth), 10 ether);
    vm.stopPrank();

    assertEq(weth.balanceOf(ALICE), _wethBalanceBefore);
  }
}
