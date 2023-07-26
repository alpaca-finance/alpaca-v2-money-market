// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseTest, console } from "../../base/BaseTest.sol";

import { MMFlatSlopeModel1 } from "../../../contracts/money-market/interest-models/MMFlatSlopeModel1.sol";

// solhint-disable func-name-mixedcase
// solhint-disable contract-name-camelcase
contract MMFlatSlopeModel1_Test is BaseTest {
  MMFlatSlopeModel1 private _flatSlopeModel1;

  function setUp() external {
    _flatSlopeModel1 = new MMFlatSlopeModel1();
  }

  function testFuzz_getInterestRate(uint256 debt, uint256 floating) external {
    // when utilization is whatever, interest will always be 6.00%
    assertEq(_flatSlopeModel1.getInterestRate(debt, floating), 0.06 ether);
  }
}
