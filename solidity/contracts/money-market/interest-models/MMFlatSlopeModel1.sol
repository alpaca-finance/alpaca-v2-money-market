// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

contract MMFlatSlopeModel1 {
  /// @dev Return the interest rate per second, using 1e18 as denom.
  function getInterestRate(uint256 debt, uint256 floating) external pure returns (uint256) {
    if (debt == 0 && floating == 0) return 0;

    return uint256(6e16) / 365 days;
  }
}
