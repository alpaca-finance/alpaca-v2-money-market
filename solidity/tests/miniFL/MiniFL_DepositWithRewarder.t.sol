// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { MiniFL_BaseTest } from "./MiniFL_BaseTest.t.sol";

import { Rewarder } from "../../contracts/miniFL/Rewarder.sol";

// interfaces
import { IMiniFL } from "../../contracts/miniFL/interfaces/IMiniFL.sol";

contract MiniFL_DepositWithRewarder is MiniFL_BaseTest {
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

  function testCorrectness_WhenDeposit_RewarderUserInfoShouldBeCorrect() external {
    uint256 _aliceWethBalanceBefore = weth.balanceOf(ALICE);
    vm.startPrank(ALICE);
    weth.approve(address(miniFL), 10 ether);
    miniFL.deposit(ALICE, wethPoolID, 10 ether);
    vm.stopPrank();

    // assert alice balance
    assertEq(_aliceWethBalanceBefore - weth.balanceOf(ALICE), 10 ether);

    // assert reward user info, both user info should be same
    _assertRewarderUserAmount(rewarder1, ALICE, wethPoolID, 10 ether);
    _assertRewarderUserAmount(rewarder2, ALICE, wethPoolID, 10 ether);
  }

  function testCorrectness_WhenDepositDebtToken_RewarderUserInfoShouldBeCorrect() external {
    uint256 _bobDebtTokenBalanceBefore = debtToken1.balanceOf(BOB);

    vm.startPrank(BOB);
    debtToken1.approve(address(miniFL), 10 ether);
    miniFL.deposit(BOB, dtokenPoolID, 10 ether);
    vm.stopPrank();

    // assert bob balance
    assertEq(_bobDebtTokenBalanceBefore - debtToken1.balanceOf(BOB), 10 ether);

    // assert reward user info
    _assertRewarderUserAmount(rewarder1, BOB, dtokenPoolID, 10 ether);
    // rewarder2 is not register in this pool then user amount should be 0
    _assertRewarderUserAmount(rewarder2, BOB, dtokenPoolID, 0 ether);
  }

  function _assertRewarderUserAmount(
    Rewarder _rewarder,
    address _user,
    uint256 _pid,
    uint256 _expectedAmount
  ) internal {
    (uint256 _amount, ) = _rewarder.userInfo(_pid, _user);
    assertEq(_amount, _expectedAmount);
  }
}
