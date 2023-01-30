// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { AV_BaseTest } from "./AV_BaseTest.t.sol";

contract AV_AdminFacetTest is AV_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  // do this when finish getters so we can assert their values after calling setters
  // TODO: add tests for setManagementFeePerSec, setInterestRateModels
}
