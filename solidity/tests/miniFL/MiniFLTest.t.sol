// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { MiniFL_BaseTest } from "./MiniFL_BaseTest.t.sol";

// interfaces
import { IRewarder } from "../../contracts/miniFL/interfaces/IRewarder.sol";

contract MiniFLTest is MiniFL_BaseTest {
  function setUp() public override {
    super.setUp();

    // allocPoint, stakingToken, rewarder, isDebtTokenPool, withUpdate
    miniFL.addPool(60, IERC20Upgradeable(address(weth)), false, false); // PID 0
    miniFL.addPool(40, IERC20Upgradeable(address(usdc)), false, false); // PID 1

    // _allocPoint, _pid, _withUpdate
    rewarder1.addPool(50, 0, false);
    rewarder1.addPool(50, 1, false);

    rewarder2.addPool(100, 0, false);
    rewarder2.addPool(0, 1, false);

    // set rewarders
    address[] memory _rewarders = new address[](2);
    _rewarders[0] = address(rewarder1);
    _rewarders[1] = address(rewarder2);
    miniFL.setPoolRewarders(0, _rewarders);
    miniFL.setPoolRewarders(1, _rewarders);

    // allocation point
    // | PID | ALPACA | Reward1 | Reward2 |
    // |   0 |     60 |      50 |     100 |
    // |   1 |     40 |      50 |       0 |
    // Reward per second
    // | ALPACA | Reward1 | Reward2 |
    // |   1000 |    1000 |    1000 |
  }

  function testCorrectness_MiniFL_ShouldWork() external {
    vm.startPrank(ALICE);
    weth.approve(address(miniFL), 10 ether);
    miniFL.deposit(ALICE, 0, 10 ether);

    usdc.approve(address(miniFL), 10 ether);
    miniFL.deposit(ALICE, 1, 10 ether);
    vm.stopPrank();

    // Expect reward when timepast 100 seconds
    // | ALPACA | Reward1 | Reward2 |
    // | 100000 |  100000 |  100000 |
    // Expectation
    // | PID | ALPACA | Reward1 | Reward2 |
    // |   0 |  60000 |   50000 |  100000 |
    // |   1 |  40000 |   50000 |       0 |

    vm.warp(block.timestamp + 100);
    assertEq(miniFL.pendingAlpaca(0, ALICE), 60000 ether);
    assertEq(rewarder1.pendingToken(0, ALICE), 50000 ether);
    assertEq(rewarder2.pendingToken(0, ALICE), 100000 ether);

    assertEq(miniFL.pendingAlpaca(1, ALICE), 40000 ether);
    assertEq(rewarder1.pendingToken(1, ALICE), 50000 ether);
    assertEq(rewarder2.pendingToken(1, ALICE), 0 ether);
  }
}
