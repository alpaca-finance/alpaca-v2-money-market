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

  function testCorrectness_getInterestRate() external {
    // when utilization is 0%, interest should be 0.00%
    assertCloseBps(_findInterestPerYear(_flatSlopeModel1.getInterestRate(0, 0)), 0, 1);

    // when utilization is 30%, interest should be close to 6.00%
    assertCloseBps(_findInterestPerYear(_flatSlopeModel1.getInterestRate(30, 70)), 0.05999999971536000 ether, 1);

    // when utilization is 60%, interest shuold be close to 6.00%
    assertCloseBps(_findInterestPerYear(_flatSlopeModel1.getInterestRate(60, 40)), 0.05999999971536000 ether, 1);

    // when utilization is 85%, interest should be close to 6.00%
    assertCloseBps(_findInterestPerYear(_flatSlopeModel1.getInterestRate(85, 15)), 0.05999999971536000 ether, 1);

    // when utilization is 90%, interest should be close to 6.00%
    assertCloseBps(_findInterestPerYear(_flatSlopeModel1.getInterestRate(90, 10)), 0.05999999971536000 ether, 1);

    // when utilization is 100%, interest should be close to 6.00%
    assertCloseBps(_findInterestPerYear(_flatSlopeModel1.getInterestRate(100, 0)), 0.05999999971536000 ether, 1);
  }
}
