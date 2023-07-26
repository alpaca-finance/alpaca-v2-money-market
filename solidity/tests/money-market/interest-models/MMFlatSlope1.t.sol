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

  function _findInterestPerYear(uint256 _interestPerSec) internal pure returns (uint256) {
    return _interestPerSec * 365 days;
  }

  function testFuzz_getInterestRate(uint256 debt, uint256 floating) external {
    // when utilization is whatever, interest will always be 5.99% ~ 6.00%
    assertEq(_findInterestPerYear(_flatSlopeModel1.getInterestRate(debt, floating)), 0.059999999999184000 ether);
  }
}
