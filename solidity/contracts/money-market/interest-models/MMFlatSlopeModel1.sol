// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

contract MMFlatSlopeModel1 {
  /// @dev Return the interest rate per second, using 1e18 as denom.
  function getInterestRate(
    uint256, /*debt*/
    uint256 /*floating*/
  ) external pure returns (uint256) {
    // 6% flat rate
    return 60000000000000000;
  }
}
