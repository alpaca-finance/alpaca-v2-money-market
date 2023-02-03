// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { BaseTest } from "../base/BaseTest.sol";

// interfaces
import { MiniFL } from "../../contracts/miniFL/MiniFL.sol";
import { Rewarder } from "../../contracts/miniFL/Rewarder.sol";

contract MiniFL_BaseTest is BaseTest {
  MiniFL internal miniFL;

  Rewarder internal rewarder1;
  Rewarder internal rewarder2;

  uint256 wethPoolID = 0;
  uint256 dtokenPoolID = 1;
  uint256 notExistsPoolID = 999;

  uint256 alpacaMaximumReward = 1000 ether;

  function setUp() public virtual {
    miniFL = deployMiniFL(address(alpaca), alpacaMaximumReward);
    miniFL.setAlpacaPerSecond(alpacaMaximumReward, false);
    alpaca.mint(address(miniFL), 10000000 ether);

    rewarder1 = deployRewarder("REWARDER01", address(miniFL), address(rewardToken1), alpacaMaximumReward);
    rewarder2 = deployRewarder("REWARDER02", address(miniFL), address(rewardToken2), alpacaMaximumReward);

    rewarder1.setRewardPerSecond(100 ether, false);
    rewarder2.setRewardPerSecond(150 ether, false);

    rewardToken1.mint(address(rewarder1), 10000 ether);
    rewardToken2.mint(address(rewarder2), 15000 ether);
  }

  function setupMiniFLPool() internal {
    // add staking pool
    miniFL.addPool(60, address(weth), false, false);
    // add debt token pool
    miniFL.addPool(40, address(debtToken1), true, false);

    // set debtToken staker
    uint256[] memory _poolIds = new uint256[](1);
    _poolIds[0] = dtokenPoolID;
    address[] memory _stakers = new address[](1);
    _stakers[0] = BOB;
    miniFL.approveStakeDebtToken(_poolIds, _stakers, true);
    debtToken1.mint(BOB, 1000 ether);
  }

  // Rewarder1 Info
  // | Pool   | AllocPoint |
  // | WETH   |         90 |
  // | DToken |         10 |
  // Rewarder2 Info
  // | Pool   | AllocPoint |
  // | DToken |        100 |
  function setupRewarder() internal {
    rewarder1.addPool(90, wethPoolID, false);
    rewarder1.addPool(10, dtokenPoolID, false);

    rewarder2.addPool(100, wethPoolID, false);

    address[] memory _poolWethRewarders = new address[](2);
    _poolWethRewarders[0] = address(rewarder1);
    _poolWethRewarders[1] = address(rewarder2);
    miniFL.setPoolRewarders(wethPoolID, _poolWethRewarders);

    address[] memory _poolDebtTokenRewarders = new address[](1);
    _poolDebtTokenRewarders[0] = address(rewarder1);
    miniFL.setPoolRewarders(dtokenPoolID, _poolDebtTokenRewarders);
  }

  function prepareForHarvest() internal {
    vm.startPrank(ALICE);
    weth.approve(address(miniFL), 20 ether);
    miniFL.deposit(ALICE, wethPoolID, 20 ether);
    vm.stopPrank();

    vm.startPrank(BOB);
    weth.approve(address(miniFL), 10 ether);
    miniFL.deposit(BOB, wethPoolID, 10 ether);
    vm.stopPrank();

    vm.startPrank(BOB);
    debtToken1.approve(address(miniFL), 90 ether);
    miniFL.deposit(BOB, dtokenPoolID, 90 ether);
    vm.stopPrank();

    vm.startPrank(BOB);
    debtToken1.approve(address(miniFL), 10 ether);
    miniFL.deposit(ALICE, dtokenPoolID, 10 ether);
    vm.stopPrank();
  }

  function assertUserInfo(
    address _user,
    uint256 _pid,
    uint256 _expectedAmount,
    int256 _expectedRewardDebt
  ) internal {
    (uint256 _amount, int256 _rewardDebt) = miniFL.userInfo(_pid, _user);
    assertEq(_amount, _expectedAmount);
    assertEq(_rewardDebt, _expectedRewardDebt);
  }

  function assertRewarderUserInfo(
    Rewarder _rewarder,
    address _user,
    uint256 _pid,
    uint256 _expectedAmount,
    int256 _expectedRewardDebt
  ) internal {
    (uint256 _amount, int256 _rewardDebt) = _rewarder.userInfo(_pid, _user);
    assertEq(_amount, _expectedAmount);
    assertEq(_rewardDebt, _expectedRewardDebt);
  }
}
