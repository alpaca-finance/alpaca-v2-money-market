// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// interfaces
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";

contract MMDoubleSlopeModel3 {
  uint256 public constant CEIL_SLOPE_1 = 85e18;
  uint256 public constant CEIL_SLOPE_2 = 85e18;
  uint256 public constant CEIL_SLOPE_3 = 100e18;

  uint256 public constant MAX_INTEREST_SLOPE_1 = 5e16;
  uint256 public constant MAX_INTEREST_SLOPE_2 = 5e16;
  uint256 public constant MAX_INTEREST_SLOPE_3 = 60e16;

  /// @dev Return the interest rate per second, using 1e18 as denom.
  function getInterestRate(uint256 debt, uint256 floating) external pure returns (uint256) {
    if (debt == 0 && floating == 0) return 0;

    uint256 total = debt + floating;
    uint256 utilization = (debt * 100e18) / total;
    if (utilization < CEIL_SLOPE_1) {
      // Less than 85% utilization - 0%-5% APY
      return (utilization * MAX_INTEREST_SLOPE_1) / (CEIL_SLOPE_1) / 365 days;
    } else if (utilization < CEIL_SLOPE_3) {
      // Between 85% and 100% - 5-60% APY
      return
        (MAX_INTEREST_SLOPE_2 +
          ((utilization - CEIL_SLOPE_2) * (MAX_INTEREST_SLOPE_3 - MAX_INTEREST_SLOPE_2)) /
          (CEIL_SLOPE_3 - CEIL_SLOPE_2)) / 365 days;
    } else {
      // Not possible, but just in case - 60% APY
      return MAX_INTEREST_SLOPE_3 / 365 days;
    }
  }
}
