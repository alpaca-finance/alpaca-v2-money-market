// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { MiniFL_BaseTest } from "./MiniFL_BaseTest.t.sol";

// interfaces
import { IMiniFL } from "../../contracts/miniFL/interfaces/IMiniFL.sol";
import { IRewarder } from "../../contracts/miniFL/interfaces/IRewarder.sol";

contract MiniFL_SetPoolTest is MiniFL_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenSetPool() external {
    miniFL.addPool(100, address(weth), false, false); // PID 0
    miniFL.addPool(50, address(usdc), false, false); // PID 1

    assertEq(miniFL.poolLength(), 2);
    assertEq(miniFL.totalAllocPoint(), 150);

    miniFL.setPool(0, 150, false);

    assertEq(miniFL.poolLength(), 2);
    assertEq(miniFL.totalAllocPoint(), 200);
  }
}
