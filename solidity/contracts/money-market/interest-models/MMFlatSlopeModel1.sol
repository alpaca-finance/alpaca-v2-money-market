// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// interfaces
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";

contract MMFlatSlopeModel1 {
  uint256 public constant CEIL_SLOPE_1 = 100e18;
  uint256 public constant CEIL_SLOPE_2 = 100e18;
  uint256 public constant CEIL_SLOPE_3 = 100e18;

  uint256 public constant MAX_INTEREST_SLOPE_1 = 6e16;
  uint256 public constant MAX_INTEREST_SLOPE_2 = 6e16;
  uint256 public constant MAX_INTEREST_SLOPE_3 = 6e16;

  /// @dev Return the interest rate per second, using 1e18 as denom.
  function getInterestRate(uint256 debt, uint256 floating) external pure returns (uint256) {
    if (debt == 0 && floating == 0) return 0;

    return uint256(MAX_INTEREST_SLOPE_3) / 365 days;
  }
}
