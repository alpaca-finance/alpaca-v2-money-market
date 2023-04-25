// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseTest, console } from "../../base/BaseTest.sol";

import { MMDoubleSlopeModel1, IInterestRateModel } from "../../../contracts/money-market/interest-models/MMDoubleSlopeModel1.sol";

// solhint-disable func-name-mixedcase
// solhint-disable contract-name-camelcase
contract MMDoubleSlope1_Test is BaseTest {
  IInterestRateModel private _doubleSlopeModel1;

  function setUp() external {
    _doubleSlopeModel1 = IInterestRateModel(address(new MMDoubleSlopeModel1()));
  }

  function _findInterestPerYear(uint256 _interestPerSec) internal pure returns (uint256) {
    return _interestPerSec * 365 days;
  }

  function testCorrectness_getInterestRate() external {
    // when utilization is 30%, interest should be 5.29%
    assertCloseBps(_findInterestPerYear(_doubleSlopeModel1.getInterestRate(30, 70)), 0.052941176 ether, 1);

    // when utilization is 60%, interest shuold be 10.588%
    assertCloseBps(_findInterestPerYear(_doubleSlopeModel1.getInterestRate(60, 40)), 0.105882353 ether, 1);

    // when utilization is 85%, interest should be 15%
    assertCloseBps(_findInterestPerYear(_doubleSlopeModel1.getInterestRate(85, 15)), 0.15 ether, 1);

    // when utilization is 90%, interest should be 76.6666%
    assertCloseBps(_findInterestPerYear(_doubleSlopeModel1.getInterestRate(90, 10)), 0.76666667 ether, 1);

    // when utilization is 100%, interest should be 200%
    assertCloseBps(_findInterestPerYear(_doubleSlopeModel1.getInterestRate(100, 0)), 2 ether, 1);
  }
}
