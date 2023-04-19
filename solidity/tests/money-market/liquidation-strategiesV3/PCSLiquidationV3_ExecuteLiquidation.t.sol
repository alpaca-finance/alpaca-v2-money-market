// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseLiqudationV3ForkTest, console } from "./BaseLiqudationV3ForkTest.sol";

// interfaces
import { IV3SwapRouter } from "solidity/contracts/money-market/interfaces/IV3SwapRouter.sol";

contract PCSLiquidationV3_ExecuteLiquidation is BaseLiqudationV3ForkTest {
  function setUp() public override {
    // TODO: setup
    // - set IB

    super.setUp();
    // mint cake to alice
    vm.startPrank(0x73feaa1eE314F8c655E354234017bE2193C9E24E);
    cake.mint(ALICE, normalizeEther(1000 ether, cakeDecimal));
    vm.stopPrank();

    // Set path
    bytes[] memory _paths = new bytes[](2);
    // - paths[cake][wbnb] = 1 hop cake + 0.25 + wbnb
    _paths[0] = abi.encodePacked(address(cake), uint24(2500), address(wbnb));
    // - paths[cake][usdt] = 2 hop cake + 0.25 + wbnb + 0.05 + usdt
    _paths[1] = abi.encodePacked(address(cake), uint24(2500), address(wbnb), uint24(500), address(usdt));
    liquidationStrat.setPaths(_paths);
  }

  // TODO: Test case
  // - testRevert_WhenExecuteLiquidation_PathConfigNotFound
  // - testCorrectness_WhenExecuteIbTokenLiquiationStrat_ShouldWork
  // - testCorrectness_WhenExecuteIbTokenLiquiationStratWithCollatValueThatLessThanRepayValue
  // - testCorrectness_WhenExecuteIbTokenLiquiationStratWithCollatValueThatMoreThanRepayValue_ShouldTransferCollatBackToUserCorreclty
  // - testRevert_WhenExecuteIbTokenLiquiationStratAndUnderlyingTokenAndRepayTokenAreSame

  function testRevert_WhenExecuteLiquidation_PathConfigNotFound() external {
    vm.prank(address(ALICE));
  }

  function test_Prank() external {}
}
