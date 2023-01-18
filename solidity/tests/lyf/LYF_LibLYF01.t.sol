// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, console } from "./LYF_BaseTest.t.sol";

// libs
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";

contract LibLYFHarness is LYF_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_Test() external {
    vm.startPrank(lyfDiamond);
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    console.log(lyfDs.moneyMarket);
  }
}
