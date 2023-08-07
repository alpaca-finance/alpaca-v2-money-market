// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseTest, console } from "../../base/BaseTest.sol";

import { MMFlatSlopeModel2 } from "../../../contracts/money-market/interest-models/MMFlatSlopeModel2.sol";

// solhint-disable func-name-mixedcase
// solhint-disable contract-name-camelcase
contract MMFlatSlopeModel2_Test is BaseTest {
  MMFlatSlopeModel2 private _flatSlopeModel2;

  function setUp() external {
    _flatSlopeModel2 = new MMFlatSlopeModel2();
  }

  function _findInterestPerYear(uint256 _interestPerSec) internal pure returns (uint256) {
    return _interestPerSec * 365 days;
  }

  function testFuzz_getInterestRate(uint256 debt, uint256 floating) external {
    // when utilization is whatever, interest will always be 4.99% ~ 5.00%
    assertEq(_findInterestPerYear(_flatSlopeModel2.getInterestRate(debt, floating)), 0.049999999994064000 ether);
  }
}
