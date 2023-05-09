// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseFork } from "./BaseFork.sol";

contract SmartTreasury_Distribute is BaseFork {
  function setUp() public override {
    super.setUp();

    // setup whitelisted caller
    // setup revenue token
    // setup allocation point
  }

  function testCorrectness_CallDistribute_ShouldWork() external {
    // rev treasury
    // dev treasury
    // burn treasury
  }

  function testRevert_UnauthorizedCallDistribute_ShouldRevert() external {}

  function testRevert_DistributeWithNonExistingRevenueToken_ShouldRevert() external {}

  function testRevert_DistributeWhenAmountTooLow_ShouldRevert() external {}
}
