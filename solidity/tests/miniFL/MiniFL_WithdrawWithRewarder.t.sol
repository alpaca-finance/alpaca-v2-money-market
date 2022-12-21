// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { MiniFL_BaseTest } from "./MiniFL_BaseTest.t.sol";

// interfaces
import { IMiniFL } from "../../contracts/miniFL/interfaces/IMiniFL.sol";

contract MiniFL_WithdrawWithRewarder is MiniFL_BaseTest {
  function setUp() public override {
    super.setUp();
    prepareMiniFLPool();

    // setup rewarder
    address[] memory _poolWethRewarders = new address[](2);
    _poolWethRewarders[0] = address(rewarder1);
    _poolWethRewarders[1] = address(rewarder2);
    miniFL.setPoolRewarders(wethPoolID, _poolWethRewarders);
    rewarder1.addPool(100, wethPoolID, false);
    rewarder2.addPool(100, wethPoolID, false);

    address[] memory _poolDebtTokenRewarders = new address[](1);
    _poolDebtTokenRewarders[0] = address(rewarder1);
    miniFL.setPoolRewarders(dtokenPoolID, _poolDebtTokenRewarders);
    rewarder1.addPool(100, dtokenPoolID, false);
  }

  function testCorrectness_WhenWithdraw_RewarderUserInfoShouldBeCorrect() external {
    // alice deposited
    vm.startPrank(ALICE);
    weth.approve(address(miniFL), 10 ether);
    miniFL.deposit(ALICE, wethPoolID, 10 ether);
    vm.stopPrank();

    uint256 _aliceWethBalanceBefore = weth.balanceOf(ALICE);

    vm.prank(ALICE);
    miniFL.withdraw(ALICE, wethPoolID, 5 ether);

    // assert alice balance
    assertEq(weth.balanceOf(ALICE) - _aliceWethBalanceBefore, 5 ether);

    // assert reward user info, both user info should be same
    _assertRewarderUserAmount(rewarder1, ALICE, wethPoolID, 5 ether);
    _assertRewarderUserAmount(rewarder2, ALICE, wethPoolID, 5 ether);
  }

  function testCorrectness_WhenWithdrawDebToken_RewarderUserInfoShouldBeCorrect() external {
    // bob deposit on debt token
    vm.startPrank(BOB);
    debtToken1.approve(address(miniFL), 10 ether);
    miniFL.deposit(BOB, dtokenPoolID, 10 ether);
    vm.stopPrank();

    uint256 _bobDTokenBalanceBefore = debtToken1.balanceOf(BOB);

    vm.prank(BOB);
    miniFL.withdraw(BOB, dtokenPoolID, 5 ether);

    // assert bob balance
    assertEq(debtToken1.balanceOf(BOB) - _bobDTokenBalanceBefore, 5 ether);

    // assert reward user info
    _assertRewarderUserAmount(rewarder1, BOB, dtokenPoolID, 5 ether);
    // rewarder2 is not register in this pool then user amount should be 0
    _assertRewarderUserAmount(rewarder2, BOB, dtokenPoolID, 0 ether);
  }
}
