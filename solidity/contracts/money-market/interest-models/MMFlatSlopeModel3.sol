// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

contract MMFlatSlopeModel3 {
  /// @dev Return the interest rate per second, using 1e18 as denom.
  function getInterestRate(
    uint256, /*debt*/
    uint256 /*floating*/
  ) external pure returns (uint256) {
    // 8% flat rate = 8e16 / 365 days
    return 2536783358;
  }
}
