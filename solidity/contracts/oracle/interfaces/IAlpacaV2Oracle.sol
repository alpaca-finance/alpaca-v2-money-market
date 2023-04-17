// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface IAlpacaV2Oracle {
  struct Config {
    address router;
    uint64 maxPriceDiffBps;
    address[] path;
    bool isUsingV3Pool;
  }

  /// @dev Set tokenConfig for getting dex price.
  function setTokenConfig(address[] calldata _tokens, Config[] calldata _configs) external;

  /// @dev Set uniswap v3 pools
  function setPools(address[] calldata _pools) external;

  /// @dev Return value in USD for the given lpAmount.
  function lpToDollar(uint256 _lpAmount, address _lpToken) external view returns (uint256, uint256);

  /// @dev Return amount of LP for the given USD.
  function dollarToLp(uint256 _dollarAmount, address _lpToken) external view returns (uint256, uint256);

  /// @dev Return value of given token in USD.
  function getTokenPrice(address _token) external view returns (uint256, uint256);

  /// @dev Return true if token price is stable.
  function isStable(address _tokenAddress) external view;

  function getPriceFromV3Pool(address _source, address _destination) external view returns (uint256 _price);

  function oracle() external view returns (address);

  function usd() external view returns (address);

  function setOracle(address _oracle) external;

  /// @dev Errors
  error AlpacaV2Oracle_InvalidLPAddress();
  error AlpacaV2Oracle_InvalidOracleAddress();
  error AlpacaV2Oracle_InvalidConfigLength();
  error AlpacaV2Oracle_InvalidConfigPath();
  error AlpacaV2Oracle_InvalidBaseStableTokenDecimal();
  error AlpacaV2Oracle_InvalidPriceDiffConfig();
  error AlpacaV2Oracle_PriceTooDeviate(uint256 _dexPrice, uint256 _oraclePrice);
}
