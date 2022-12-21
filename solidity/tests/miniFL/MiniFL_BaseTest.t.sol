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

  function setUp() public virtual {
    uint256 _maximumReward = 1000 ether;
    miniFL = deployMiniFL(address(alpaca), _maximumReward);
    miniFL.setAlpacaPerSecond(_maximumReward, false);

    rewarder1 = deployRewarder("REWARDER01", address(miniFL), address(rewardToken1), _maximumReward);
    rewarder2 = deployRewarder("REWARDER02", address(miniFL), address(rewardToken2), _maximumReward);

    rewarder1.setRewardPerSecond(_maximumReward, false);
    rewarder2.setRewardPerSecond(_maximumReward, false);
  }

  function prepareMiniFLPool() internal {
    // add staking pool
    miniFL.addPool(100, IERC20Upgradeable(address(weth)), false, false);
    // add debt token pool
    miniFL.addPool(100, IERC20Upgradeable(address(debtToken1)), true, false);

    // set debtToken staker
    uint256[] memory _poolIds = new uint256[](1);
    _poolIds[0] = dtokenPoolID;
    address[] memory _stakers = new address[](1);
    _stakers[0] = BOB;
    miniFL.approveStakeDebtToken(_poolIds, _stakers, true);
    debtToken1.mint(BOB, 1000 ether);
  }
}
