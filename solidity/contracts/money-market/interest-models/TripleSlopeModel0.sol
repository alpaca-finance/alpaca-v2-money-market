// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// interfaces
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";

contract TripleSlopeModel0 {
  uint256 public constant CEIL_SLOPE_1 = 80e18;
  uint256 public constant CEIL_SLOPE_2 = 80e18;
  uint256 public constant CEIL_SLOPE_3 = 100e18;

  uint256 public constant MAX_INTEREST_SLOPE_1 = 10e16;
  uint256 public constant MAX_INTEREST_SLOPE_2 = 10e16;
  uint256 public constant MAX_INTEREST_SLOPE_3 = 40e16;

  /// @dev Return the interest rate per second, using 1e18 as denom.
  function getInterestRate(uint256 debt, uint256 floating) external pure returns (uint256) {
    if (debt == 0 && floating == 0) return 0;

    uint256 total = debt + floating;
    uint256 utilization = (debt * 100e18) / total;
    if (utilization < CEIL_SLOPE_1) {
      // Less than 80% utilization - 0%-10% APY
      return (utilization * MAX_INTEREST_SLOPE_1) / (CEIL_SLOPE_1) / 365 days;
    } else if (utilization < CEIL_SLOPE_3) {
      // Between 90% and 100% - 10-40% APY
      return
        (MAX_INTEREST_SLOPE_2 +
          ((utilization - CEIL_SLOPE_2) * (MAX_INTEREST_SLOPE_3 - MAX_INTEREST_SLOPE_2)) /
          (CEIL_SLOPE_3 - CEIL_SLOPE_2)) / 365 days;
    } else {
      // Not possible, but just in case - 40% APY
      return MAX_INTEREST_SLOPE_3 / 365 days;
    }
  }
}
