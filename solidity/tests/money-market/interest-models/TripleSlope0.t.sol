// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseTest, console } from "../../base/BaseTest.sol";

import { TripleSlopeModel0, IInterestRateModel } from "../../../contracts/money-market/interest-models/TripleSlopeModel0.sol";

// solhint-disable func-name-mixedcase
// solhint-disable contract-name-camelcase
contract TripleSlope0_Test is BaseTest {
  IInterestRateModel private _tripleSlopeModel0;

  function setUp() external {
    _tripleSlopeModel0 = IInterestRateModel(address(new TripleSlopeModel0()));
  }

  function _findInterestPerYear(uint256 _interestPerSec) internal pure returns (uint256) {
    return _interestPerSec * 365 days;
  }

  function testCorrectness_getInterestRate() external {
    // when utilization is 30%, interest should be 3.75%
    assertCloseBps(_findInterestPerYear(_tripleSlopeModel0.getInterestRate(30, 70)), 0.0375 ether, 1);

    // when utilization is 60%, interest shuold be 7.5%
    assertCloseBps(_findInterestPerYear(_tripleSlopeModel0.getInterestRate(60, 40)), 0.075 ether, 1);

    // when utilization is 80%, interest should be 10%
    assertCloseBps(_findInterestPerYear(_tripleSlopeModel0.getInterestRate(80, 20)), 0.1 ether, 1);

    // when utilization is 90%, interest should be 25%
    assertCloseBps(_findInterestPerYear(_tripleSlopeModel0.getInterestRate(90, 10)), 0.25 ether, 1);

    // when utilization is 100%, interest should be 40%
    assertCloseBps(_findInterestPerYear(_tripleSlopeModel0.getInterestRate(100, 0)), 0.4 ether, 1);
  }
}
