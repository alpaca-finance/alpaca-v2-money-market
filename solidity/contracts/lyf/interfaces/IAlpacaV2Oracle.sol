// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface IAlpacaV2Oracle {
  /// @dev Return value in USD for the given lpAmount.
  function lpToDollar(uint256 _lpAmount, address _pancakeLPToken) external view returns (uint256, uint256);

  /// @dev Return amount of LP for the given USD.
  function dollarToLp(uint256 _dollarAmount, address _lpToken) external view returns (uint256, uint256);

  /// @dev Return value of given token in USD.
  function getTokenPrice(address _token) external view returns (uint256, uint256);

  /// @dev Errors
  error AlpacaV2Oracle_InvalidLPAddress();
  error AlpacaV2Oracle_InvalidOracleAddress();
}
