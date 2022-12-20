// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BaseTest } from "../base/BaseTest.sol";

// interfaces
import { MiniFL } from "../../contracts/miniFL/MiniFL.sol";
import { Rewarder } from "../../contracts/miniFL/Rewarder.sol";

contract MiniFL_BaseTest is BaseTest {
  MiniFL internal miniFL;

  Rewarder internal rewarder1;
  Rewarder internal rewarder2;

  function setUp() public virtual {
    uint256 _maximumReward = 1000 ether;
    miniFL = deployMiniFL(address(alpaca), _maximumReward);
    miniFL.setAlpacaPerSecond(_maximumReward, false);

    rewarder1 = deployRewarder("REWARDER01", address(miniFL), address(rewardToken1), _maximumReward);
    rewarder2 = deployRewarder("REWARDER02", address(miniFL), address(rewardToken2), _maximumReward);

    rewarder1.setRewardPerSecond(_maximumReward, false);
    rewarder2.setRewardPerSecond(_maximumReward, false);
  }
}
