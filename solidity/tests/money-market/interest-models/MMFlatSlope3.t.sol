// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseTest, console } from "../../base/BaseTest.sol";

import { MMFlatSlopeModel3 } from "../../../contracts/money-market/interest-models/MMFlatSlopeModel3.sol";

// solhint-disable func-name-mixedcase
// solhint-disable contract-name-camelcase
contract MMFlatSlopeModel3_Test is BaseTest {
  MMFlatSlopeModel3 private _flatSlopeModel3;

  function setUp() external {
    _flatSlopeModel3 = new MMFlatSlopeModel3();
  }

  function _findInterestPerYear(uint256 _interestPerSec) internal pure returns (uint256) {
    return _interestPerSec * 365 days;
  }

  function testFuzz_getInterestRate(uint256 debt, uint256 floating) external {
    // when utilization is whatever, interest will always be 7.99% ~ 8.00%
    assertEq(_findInterestPerYear(_flatSlopeModel3.getInterestRate(debt, floating)), 0.079999999977888000 ether);
  }
}
