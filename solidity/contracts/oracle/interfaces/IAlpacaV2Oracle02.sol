// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface IAlpacaV2Oracle02 {
  /// @dev Errors
  error AlpacaV2Oracle02_InvalidLPAddress();
  error AlpacaV2Oracle02_InvalidOracleAddress();
  error AlpacaV2Oracle02_InvalidBaseStableTokenDecimal();

  /// @dev Set uniswap v3 pools
  function setPools(address[] calldata _pools) external;

  /// @dev Return value in USD for the given lpAmount.
  function lpToDollar(uint256 _lpAmount, address _lpToken) external view returns (uint256, uint256);

  /// @dev Return amount of LP for the given USD.
  function dollarToLp(uint256 _dollarAmount, address _lpToken) external view returns (uint256, uint256);

  /// @dev Return value of given token in USD.
  function getTokenPrice(address _token) external view returns (uint256, uint256);

  /// @dev Set new oracle.
  function setOracle(address _oracle) external;

  /// @dev Return true if token price is stable.
  function isStable(address _tokenAddress) external view;

  function getPriceFromV3Pool(address _source, address _destination) external view returns (uint256 _price);

  function oracle() external view returns (address);

  function usd() external view returns (address);
}
