// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { MiniFL_BaseTest } from "./MiniFL_BaseTest.t.sol";

// libs
import { LibAccount } from "../libs/LibAccount.sol";

// interfaces
import { IMiniFL } from "../../contracts/miniFL/interfaces/IMiniFL.sol";

contract MiniFL_PendingAlpaca is MiniFL_BaseTest {
  using LibAccount for address;

  function setUp() public override {
    super.setUp();
    setupMiniFLPool();
    prepareForHarvest();
  }

  // note:
  // block timestamp start at 1
  // alpaca per second is 1000 ether
  // weth pool alloc point is 60%
  // dtoken pool alloc point is 40%

  function testCorrectness_WhenTimpast_PendingRewardShouldBeCorrectly() external {
    // timpast for 100 second
    vm.warp(block.timestamp + 100);
    // alpaca reward distributed 1000 * 100 = 100000 ether
    // | Staking Token | ALICE | BOB | Total | ALLOC Point | ALPACA Reward |
    // |          WETH |    20 |  10 |    30 |    60 (60%) |         60000 |
    // |        DToken |    10 |  90 |   100 |    40 (40%) |         40000 |
    // WETHPool accRewardPerShare is 60000 / 30 = 2000
    // DTOKENPool accRewardPerShare is 40000 / 100 = 400

    // in weth pool alice staked 20, bob staked 10
    // in dtoken pool alice staked 10, bob staked 90

    // alice pending alpaca = 2000 * 20 = 40000 ether
    assertEq(miniFL.pendingAlpaca(wethPoolID, ALICE), 40000 ether);
    // bob pending alpaca = 2000 * 10 = 20000 ether
    assertEq(miniFL.pendingAlpaca(wethPoolID, BOB), 20000 ether);

    // alice pending alpaca = 400 * 10 = 4000 ether
    assertEq(miniFL.pendingAlpaca(dtokenPoolID, ALICE), 4000 ether);
    // bob pending alpaca = 400 * 90 = 36000 ether
    assertEq(miniFL.pendingAlpaca(dtokenPoolID, BOB), 36000 ether);
  }
}
