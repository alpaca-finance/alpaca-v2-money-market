// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// interfaces
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";

contract FixedInterestRateModel is IInterestRateModel {
  uint256 decimal;

  constructor(uint256 _decimal) {
    decimal = _decimal;
  }

  /// @dev Return a static interest rate per second = 0.1
  function getInterestRate(
    uint256 debt,
    uint256 /*floating*/
  ) external view returns (uint256 _interestRate) {
    return (debt * 10**(18 - decimal)) / 1000;
  }
}
