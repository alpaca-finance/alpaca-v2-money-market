// SPDX-License-Identifier: BUSL
/**
  ∩~~~~∩ 
  ξ ･×･ ξ 
  ξ　~　ξ 
  ξ　　 ξ 
  ξ　　 “~～~～〇 
  ξ　　　　　　 ξ 
  ξ ξ ξ~～~ξ ξ ξ 
　 ξ_ξξ_ξ　ξ_ξξ_ξ
Alpaca Fin Corporation
*/
pragma solidity 0.8.17;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IPriceOracle } from "./interfaces/IPriceOracle.sol";
import { IAggregatorV3 } from "./interfaces/IAggregatorV3.sol";

contract ChainLinkPriceOracle2 is OwnableUpgradeable, IPriceOracle {
  /// ---------------------------------------------------
  /// Errors
  /// ---------------------------------------------------
  error ChainlinkPriceOracle_InconsistentLength();
  error ChainlinkPriceOracle_InvalidPrice();
  error ChainlinkPriceOracle_NoSource();
  error ChainlinkPriceOracle_SourceExistedPair();
  error ChainlinkPriceOracle_SourceOverLimit();

  /// ---------------------------------------------------
  /// State
  /// ---------------------------------------------------
  /// @dev Mapping from token0, token1 to sources
  mapping(address => mapping(address => mapping(uint256 => IAggregatorV3))) public priceFeeds;
  mapping(address => mapping(address => uint256)) public priceFeedCount;

  /// ---------------------------------------------------
  /// Event
  /// ---------------------------------------------------
  event LogSetPriceFeed(address indexed token0, address indexed token1, IAggregatorV3[] sources);

  function initialize() external initializer {
    OwnableUpgradeable.__Ownable_init();
  }

  /// @dev Set sources for multiple token pairs
  /// @param token0s Token0 address to set source
  /// @param token1s Token1 address to set source
  /// @param allSources source for the token pair
  function setPriceFeeds(
    address[] calldata token0s,
    address[] calldata token1s,
    IAggregatorV3[][] calldata allSources
  ) external onlyOwner {
    // Check
    if (token0s.length != token1s.length || token0s.length != allSources.length)
      revert ChainlinkPriceOracle_InconsistentLength();

    for (uint256 idx = 0; idx < token0s.length; ) {
      _setPriceFeed(token0s[idx], token1s[idx], allSources[idx]);
      unchecked {
        idx++;
      }
    }
  }

  /// @dev Set source for the token pair
  /// @param token0 Token0 address to set source
  /// @param token1 Token1 address to set source
  /// @param sources source for the token pair
  function _setPriceFeed(
    address token0,
    address token1,
    IAggregatorV3[] memory sources
  ) internal {
    // Check
    if (priceFeedCount[token1][token0] > 0) revert ChainlinkPriceOracle_SourceExistedPair();
    if (sources.length > 2) revert ChainlinkPriceOracle_SourceOverLimit();

    // Effect
    priceFeedCount[token0][token1] = sources.length;
    for (uint256 idx = 0; idx < sources.length; ) {
      priceFeeds[token0][token1][idx] = sources[idx];
      unchecked {
        idx++;
      }
    }

    emit LogSetPriceFeed(token0, token1, sources);
  }

  /// @dev Return the price of token0/token1, multiplied by 1e18
  /// @param token0 Token0 to set oracle sources
  /// @param token1 Token1 to set oracle sources
  function getPrice(address token0, address token1) public view override returns (uint256, uint256) {
    if (uint256(priceFeedCount[token0][token1]) == 0 && uint256(priceFeedCount[token1][token0]) == 0)
      revert ChainlinkPriceOracle_NoSource();

    uint256 _price1 = 0;
    uint256 _price2 = 0;
    uint256 _lastUpdate1 = 0;
    uint256 _lastUpdate2 = 0;

    if (priceFeedCount[token0][token1] != 0) {
      (_price1, _lastUpdate1) = _extractPriceFeeds(token0, token1, 0, false);
      if (priceFeedCount[token0][token1] == 2) {
        (_price2, _lastUpdate2) = _extractPriceFeeds(token0, token1, 1, false);
        return ((_price1 * 1e18) / _price2, _lastUpdate2 < _lastUpdate1 ? _lastUpdate2 : _lastUpdate1);
      }
      return (_price1, _lastUpdate1);
    }

    (_price1, _lastUpdate1) = _extractPriceFeeds(token1, token0, 0, true);
    if (priceFeedCount[token1][token0] == 2) {
      (_price2, _lastUpdate2) = _extractPriceFeeds(token1, token0, 1, true);
      return ((_price1 * 1e18) / _price2, _lastUpdate2 < _lastUpdate1 ? _lastUpdate2 : _lastUpdate1);
    }

    return (_price1, _lastUpdate1);
  }

  function _extractPriceFeeds(
    address token0,
    address token1,
    uint8 index,
    bool reversedPair
  ) internal view returns (uint256, uint256) {
    IAggregatorV3 priceFeed = priceFeeds[token0][token1][index];
    (, int256 answer, , uint256 lastUpdate, ) = priceFeed.latestRoundData();
    uint256 decimals = uint256(priceFeed.decimals());

    uint256 price = reversedPair
      ? ((10**decimals) * 1e18) / uint256(answer)
      : ((uint256(answer) * 1e18) / (10**decimals));

    return (price, lastUpdate);
  }
}
