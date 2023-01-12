// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface IAlpacaV2Oracle {
  struct Config {
    address router;
    address[] path;
    uint64 maxPriceDiff;
  }

  /// @dev Set tokenConfig for getting dex price.
  function setTokenConfig(address[] calldata _tokens, Config[] calldata _configs) external;

  /// @dev Return value in USD for the given lpAmount.
  function lpToDollar(uint256 _lpAmount, address _lpToken) external view returns (uint256, uint256);

  /// @dev Return amount of LP for the given USD.
  function dollarToLp(uint256 _dollarAmount, address _lpToken) external view returns (uint256, uint256);

  /// @dev Return value of given token in USD.
  function getTokenPrice(address _token) external view returns (uint256, uint256);

  /// @dev Return true if token price is stable.
  function isStable(address _tokenAddress) external view returns (bool);

  /// @dev Errors
  error AlpacaV2Oracle_InvalidLPAddress();
  error AlpacaV2Oracle_InvalidOracleAddress();
  error AlpacaV2Oracle_InvalidConfigLength();
  error AlpacaV2Oracle_InvalidConfigPath();
  error AlpacaV2Oracle_PriceTooDeviate(uint256 _dexPrice, uint256 _oraclePrice);
}
