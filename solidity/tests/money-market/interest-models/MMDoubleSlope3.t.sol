// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseTest, console } from "../../base/BaseTest.sol";

import { MMDoubleSlopeModel3, IInterestRateModel } from "../../../contracts/money-market/interest-models/MMDoubleSlopeModel3.sol";

// solhint-disable func-name-mixedcase
// solhint-disable contract-name-camelcase
contract MMDoubleSlope3_Test is BaseTest {
  IInterestRateModel private _doubleSlopeModel3;

  function setUp() external {
    _doubleSlopeModel3 = IInterestRateModel(address(new MMDoubleSlopeModel3()));
  }

  function _findInterestPerYear(uint256 _interestPerSec) internal pure returns (uint256) {
    return _interestPerSec * 365 days;
  }

  function testCorrectness_getInterestRate() external {
    // when utilization is 30%, interest should be 1.7644%
    assertCloseBps(_findInterestPerYear(_doubleSlopeModel3.getInterestRate(30, 70)), 0.017647059 ether, 1);

    // when utilization is 60%, interest shuold be 3.529%
    assertCloseBps(_findInterestPerYear(_doubleSlopeModel3.getInterestRate(60, 40)), 0.035294118 ether, 1);

    // when utilization is 85%, interest should be 5%
    assertCloseBps(_findInterestPerYear(_doubleSlopeModel3.getInterestRate(85, 15)), 0.050000000 ether, 1);

    // when utilization is 90%, interest should be 23.33333%
    assertCloseBps(_findInterestPerYear(_doubleSlopeModel3.getInterestRate(90, 10)), 0.23333333 ether, 1);

    // when utilization is 100%, interest should be 60%
    assertCloseBps(_findInterestPerYear(_doubleSlopeModel3.getInterestRate(100, 0)), 0.6 ether, 1);
  }
}
