// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// interfaces
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";

contract MMDoubleSlopeModel1 {
  uint256 public constant CEIL_SLOPE_1 = 85e18;
  uint256 public constant CEIL_SLOPE_2 = 85e18;
  uint256 public constant CEIL_SLOPE_3 = 100e18;

  uint256 public constant MAX_INTEREST_SLOPE_1 = 15e16;
  uint256 public constant MAX_INTEREST_SLOPE_2 = 15e16;
  uint256 public constant MAX_INTEREST_SLOPE_3 = 2e18;

  /// @dev Return the interest rate per second, using 1e18 as denom.
  function getInterestRate(uint256 debt, uint256 floating) external pure returns (uint256) {
    if (debt == 0 && floating == 0) return 0;

    uint256 total = debt + floating;
    uint256 utilization = (debt * 100e18) / total;
    if (utilization < CEIL_SLOPE_1) {
      // Less than 85% utilization - 0%-15% APY
      return (utilization * MAX_INTEREST_SLOPE_1) / (CEIL_SLOPE_1) / 365 days;
    } else if (utilization < CEIL_SLOPE_3) {
      // Between 90% and 100% - 15-200% APY
      return
        (MAX_INTEREST_SLOPE_2 +
          ((utilization - CEIL_SLOPE_2) * (MAX_INTEREST_SLOPE_3 - MAX_INTEREST_SLOPE_2)) /
          (CEIL_SLOPE_3 - CEIL_SLOPE_2)) / 365 days;
    } else {
      // Not possible, but just in case - 200% APY
      return MAX_INTEREST_SLOPE_3 / 365 days;
    }
  }
}
