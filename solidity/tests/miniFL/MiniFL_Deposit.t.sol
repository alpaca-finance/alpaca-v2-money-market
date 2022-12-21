// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { MiniFL_BaseTest } from "./MiniFL_BaseTest.t.sol";

// interfaces
import { IMiniFL } from "../../contracts/miniFL/interfaces/IMiniFL.sol";
import { IRewarder } from "../../contracts/miniFL/interfaces/IRewarder.sol";

contract MiniFL_Deposit is MiniFL_BaseTest {
  uint256 wethPoolID = 0;
  uint256 debtTokenPoolID = 1;
  uint256 notExistsPoolID = 999;

  function setUp() public override {
    super.setUp();

    miniFL.addPool(100, IERC20Upgradeable(address(weth)), false, false);
    miniFL.addPool(100, IERC20Upgradeable(address(debtToken1)), true, false);

    // set debtToken staker
    uint256[] memory _poolIds = new uint256[](1);
    _poolIds[0] = debtTokenPoolID;
    address[] memory _stakers = new address[](1);
    _stakers[0] = BOB;
    miniFL.approveStakeDebtToken(_poolIds, _stakers, true);
    debtToken1.mint(BOB, 1000 ether);
  }

  function testRevert_WhenDepositOnNotExistsPool() external {
    vm.startPrank(ALICE);
    vm.expectRevert();
    miniFL.deposit(ALICE, notExistsPoolID, 10 ether);
    vm.stopPrank();
  }

  // #deposit ibToken (not debt token)
  function testCorrectness_WhenDeposit() external {
    uint256 _aliceWethBalanceBefore = weth.balanceOf(ALICE);
    vm.startPrank(ALICE);
    weth.approve(address(miniFL), 10 ether);
    miniFL.deposit(ALICE, wethPoolID, 10 ether);
    vm.stopPrank();

    assertEq(_aliceWethBalanceBefore - weth.balanceOf(ALICE), 10 ether);
  }

  function testRevert_WhenDepositForAnother() external {
    // deposit for ALICE
    vm.expectRevert(abi.encodeWithSelector(IMiniFL.MiniFL_Forbidden.selector));
    miniFL.deposit(ALICE, wethPoolID, 10 ether);
  }

  // #deposit debtToken
  function testCorrectness_WhenDepositDebtToken() external {
    uint256 _bobDebtTokenBalanceBefore = debtToken1.balanceOf(BOB);

    vm.startPrank(BOB);
    debtToken1.approve(address(miniFL), 10 ether);
    miniFL.deposit(BOB, debtTokenPoolID, 10 ether);
    vm.stopPrank();

    assertEq(_bobDebtTokenBalanceBefore - debtToken1.balanceOf(BOB), 10 ether);
  }

  // note: now debt token can depost for another
  function testCorrectness_WhenDepositDebtTokenForAnother() external {
    uint256 _bobDebtTokenBalanceBefore = debtToken1.balanceOf(BOB);
    // BOB deposit for ALICE
    vm.startPrank(BOB);
    debtToken1.approve(address(miniFL), 10 ether);
    miniFL.deposit(ALICE, debtTokenPoolID, 10 ether);
    vm.stopPrank();

    assertEq(_bobDebtTokenBalanceBefore - debtToken1.balanceOf(BOB), 10 ether);
  }

  function testRevert_WhenNotAllowToDepositDebtToken() external {
    // alice is not debt token staker
    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(IMiniFL.MiniFL_Forbidden.selector));
    miniFL.deposit(BOB, debtTokenPoolID, 10 ether);
    vm.stopPrank();
  }
}
