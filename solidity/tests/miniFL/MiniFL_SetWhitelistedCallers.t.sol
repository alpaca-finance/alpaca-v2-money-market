// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MiniFL_BaseTest } from "./MiniFL_BaseTest.t.sol";

// interfaces
import { IMiniFL } from "../../contracts/miniFL/interfaces/IMiniFL.sol";

contract MiniFL_SetWhitelistedCallersTest is MiniFL_BaseTest {
  address[] _callers;

  function setUp() public override {
    super.setUp();

    _callers = new address[](2);
    _callers[0] = ALICE;
    _callers[1] = BOB;
  }

  function testCorrectness_WhenSetWhitelistedCallers() external {
    // ALICE and BOB are non-whitelisted callers yet.
    assertTrue(!miniFL.whitelistedCallers(ALICE));
    assertTrue(!miniFL.whitelistedCallers(BOB));

    // set ALICE and BOB as whitelisted callers
    miniFL.setWhitelistedCallers(_callers, true);

    assertTrue(miniFL.whitelistedCallers(ALICE));
    assertTrue(miniFL.whitelistedCallers(BOB));
  }

  function testRevert_WhenNonOwnerSetWhitelistedCallers() external {
    vm.startPrank(CAT);
    vm.expectRevert("Ownable: caller is not the owner");

    miniFL.setWhitelistedCallers(_callers, true);
    vm.stopPrank();
  }
}
