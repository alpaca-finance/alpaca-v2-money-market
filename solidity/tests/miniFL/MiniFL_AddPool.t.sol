// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { MiniFL_BaseTest } from "./MiniFL_BaseTest.t.sol";

// interfaces
import { IMiniFL } from "../../contracts/miniFL/interfaces/IMiniFL.sol";
import { IRewarder } from "../../contracts/miniFL/interfaces/IRewarder.sol";

contract MiniFL_AddPoolTest is MiniFL_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenAddPool() external {
    assertEq(miniFL.poolLength(), 0);
    assertEq(miniFL.totalAllocPoint(), 0);

    miniFL.addPool(100, address(weth), false, false);
    miniFL.addPool(50, address(usdc), false, false);

    assertEq(miniFL.poolLength(), 2);
    assertEq(miniFL.totalAllocPoint(), 150);
  }

  function testRevert_WhenNonWhitelistedCallersAddPool() external {
    vm.startPrank(CAT);
    vm.expectRevert(abi.encodeWithSelector(IMiniFL.MiniFL_Unauthorized.selector));
    miniFL.addPool(100, address(weth), false, false);
    vm.stopPrank();
  }

  function testRevert_WhenAddDuplicatedStakingTokenPool() external {
    miniFL.addPool(100, address(weth), false, false);
    vm.expectRevert(abi.encodeWithSelector(IMiniFL.MiniFL_DuplicatePool.selector));
    miniFL.addPool(100, address(weth), false, false);
  }
}
