// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseTest, console } from "../../base/BaseTest.sol";

import { MMDoubleSlopeModel2, IInterestRateModel } from "../../../contracts/money-market/interest-models/MMDoubleSlopeModel2.sol";

// solhint-disable func-name-mixedcase
// solhint-disable contract-name-camelcase
contract MMDoubleSlope2_Test is BaseTest {
  IInterestRateModel private _doubleSlopeModel2;

  function setUp() external {
    _doubleSlopeModel2 = IInterestRateModel(address(new MMDoubleSlopeModel2()));
  }

  function _findInterestPerYear(uint256 _interestPerSec) internal pure returns (uint256) {
    return _interestPerSec * 365 days;
  }

  function testCorrectness_getInterestRate() external {
    // when utilization is 30%, interest should be 3.5294%
    assertCloseBps(_findInterestPerYear(_doubleSlopeModel2.getInterestRate(30, 70)), 0.035294118 ether, 1);

    // when utilization is 60%, interest shuold be 7.0588%
    assertCloseBps(_findInterestPerYear(_doubleSlopeModel2.getInterestRate(60, 40)), 0.070588235 ether, 1);

    // when utilization is 85%, interest should be 10%
    assertCloseBps(_findInterestPerYear(_doubleSlopeModel2.getInterestRate(85, 15)), 0.1 ether, 1);

    // when utilization is 90%, interest should be 33.333%
    assertCloseBps(_findInterestPerYear(_doubleSlopeModel2.getInterestRate(90, 10)), 0.33333333 ether, 1);

    // when utilization is 100%, interest should be 80%
    assertCloseBps(_findInterestPerYear(_doubleSlopeModel2.getInterestRate(100, 0)), 0.8 ether, 1);
  }
}
