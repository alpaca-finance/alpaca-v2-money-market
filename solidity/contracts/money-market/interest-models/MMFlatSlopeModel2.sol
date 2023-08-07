// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

contract MMFlatSlopeModel2 {
  /// @dev Return the interest rate per second, using 1e18 as denom.
  function getInterestRate(
    uint256, /*debt*/
    uint256 /*floating*/
  ) external pure returns (uint256) {
    // 5% flat rate = 5e16 / 365 days
    return 1585489599;
  }
}
