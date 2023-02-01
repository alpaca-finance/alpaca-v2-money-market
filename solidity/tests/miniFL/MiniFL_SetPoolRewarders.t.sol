// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { MiniFL_BaseTest } from "./MiniFL_BaseTest.t.sol";

// interfaces
import { MiniFL } from "../../contracts/miniFL/MiniFL.sol";
import { IMiniFL } from "../../contracts/miniFL/interfaces/IMiniFL.sol";
import { IRewarder } from "../../contracts/miniFL/interfaces/IRewarder.sol";

contract MiniFL_SetPoolRewarders is MiniFL_BaseTest {
  function setUp() public override {
    super.setUp();
    setupMiniFLPool();
  }

  function testCorrectness_WhenSetPoolRewarders() external {
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

    assertEq(miniFL.rewarders(wethPoolID, 0), address(rewarder1));
    assertEq(miniFL.rewarders(wethPoolID, 1), address(rewarder2));
    assertEq(miniFL.rewarders(dtokenPoolID, 0), address(rewarder1));
  }

  function testRevert_WhenSetRewarderWithWrongMiniFL() external {
    MiniFL otherMiniFL = deployMiniFL(address(alpaca), alpacaMaximumReward);

    IRewarder _newRewarder = deployRewarder(
      "NewRewarder",
      address(otherMiniFL),
      address(rewardToken1),
      alpacaMaximumReward
    );

    address[] memory _poolDebtTokenRewarders = new address[](2);
    _poolDebtTokenRewarders[0] = address(_newRewarder);
    _poolDebtTokenRewarders[1] = address(rewarder1);
    vm.expectRevert(abi.encodeWithSelector(IMiniFL.MiniFL_BadRewarder.selector));
    miniFL.setPoolRewarders(dtokenPoolID, _poolDebtTokenRewarders);
  }
}
