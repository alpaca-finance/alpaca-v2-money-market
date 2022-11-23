// SPDX-License-Identifier: BUSL

pragma solidity 0.8.17;
pragma experimental ABIEncoderV2;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IPriceOracle } from "./interfaces/IPriceOracle.sol";

import { LibFullMath } from "./libraries/LibFullMath.sol";

contract OracleMedianizer is OwnableUpgradeable, IPriceOracle {
  using LibFullMath for uint256;

  // Mapping from token0, token1 to number of sources
  mapping(address => mapping(address => uint256)) public primarySourceCount;
  // Mapping from token0, token1 to (mapping from index to oracle source)
  mapping(address => mapping(address => mapping(uint256 => IPriceOracle))) public primarySources;
  // Mapping from token0, token1 to max price deviation (multiplied by 1e18)
  mapping(address => mapping(address => uint256)) public maxPriceDeviations;
  // Mapping from token0, token1 to max price stale (seconds)
  mapping(address => mapping(address => uint256)) public maxPriceStales;
  // min price deviation
  uint256 public constant MIN_PRICE_DEVIATION = 1e18;
  // max price deviation
  uint256 public constant MAX_PRICE_DEVIATION = 1.5e18;

  event SetPrimarySources(
    address indexed token0,
    address indexed token1,
    uint256 maxPriceDeviation,
    uint256 maxPriceStale,
    IPriceOracle[] oracles
  );

  function initialize() external initializer {
    OwnableUpgradeable.__Ownable_init();
  }

  /// @dev Set oracle primary sources for the token pair
  /// @param token0 Token0 address to set oracle sources
  /// @param token1 Token1 address to set oracle sources
  /// @param maxPriceDeviation Max price deviation (in 1e18) for token pair
  /// @param maxPriceStale Max price stale (in seconds) for token pair
  /// @param sources Oracle sources for the token pair
  function setPrimarySources(
    address token0,
    address token1,
    uint256 maxPriceDeviation,
    uint256 maxPriceStale,
    IPriceOracle[] calldata sources
  ) external onlyOwner {
    _setPrimarySources(token0, token1, maxPriceDeviation, maxPriceStale, sources);
  }

  /// @dev Set oracle primary sources for multiple token pairs
  /// @param token0s List of token0 addresses to set oracle sources
  /// @param token1s List of token1 addresses to set oracle sources
  /// @param maxPriceDeviationList List of max price deviations (in 1e18) for token pairs
  /// @param maxPriceStaleList List of Max price stale (in seconds) for token pair
  /// @param allSources List of oracle sources for token pairs
  function setMultiPrimarySources(
    address[] calldata token0s,
    address[] calldata token1s,
    uint256[] calldata maxPriceDeviationList,
    uint256[] calldata maxPriceStaleList,
    IPriceOracle[][] calldata allSources
  ) external onlyOwner {
    require(
      token0s.length == token1s.length &&
        token0s.length == allSources.length &&
        token0s.length == maxPriceDeviationList.length &&
        token0s.length == maxPriceStaleList.length,
      "OracleMedianizer::setMultiPrimarySources:: inconsistent length"
    );
    for (uint256 idx = 0; idx < token0s.length; idx++) {
      _setPrimarySources(
        token0s[idx],
        token1s[idx],
        maxPriceDeviationList[idx],
        maxPriceStaleList[idx],
        allSources[idx]
      );
    }
  }

  /// @dev Set oracle primary sources for token pair
  /// @param token0 Token0 to set oracle sources
  /// @param token1 Token1 to set oracle sources
  /// @param maxPriceDeviation Max price deviation (in 1e18) for token pair
  /// @param maxPriceStale Max price stale (in seconds) for token pair
  /// @param sources Oracle sources for the token pair
  function _setPrimarySources(
    address token0,
    address token1,
    uint256 maxPriceDeviation,
    uint256 maxPriceStale,
    IPriceOracle[] memory sources
  ) internal {
    require(
      maxPriceDeviation >= MIN_PRICE_DEVIATION && maxPriceDeviation <= MAX_PRICE_DEVIATION,
      "OracleMedianizer::setPrimarySources:: bad max deviation value"
    );
    require(sources.length <= 3, "OracleMedianizer::setPrimarySources:: sources length exceed 3");
    primarySourceCount[token0][token1] = sources.length;
    primarySourceCount[token1][token0] = sources.length;
    maxPriceDeviations[token0][token1] = maxPriceDeviation;
    maxPriceDeviations[token1][token0] = maxPriceDeviation;
    maxPriceStales[token0][token1] = maxPriceStale;
    maxPriceStales[token1][token0] = maxPriceStale;
    for (uint256 idx = 0; idx < sources.length; idx++) {
      primarySources[token0][token1][idx] = sources[idx];
      primarySources[token1][token0][idx] = sources[idx];
    }
    emit SetPrimarySources(token0, token1, maxPriceDeviation, maxPriceStale, sources);
  }

  /// @dev Return token0/token1 price
  /// @param token0 Token0 to get price of
  /// @param token1 Token1 to get price of
  /// NOTE: Support at most 3 oracle sources per token
  function _getPrice(address token0, address token1) internal view returns (uint256) {
    uint256 candidateSourceCount = primarySourceCount[token0][token1];
    require(candidateSourceCount > 0, "OracleMedianizer::getPrice:: no primary source");
    uint256[] memory prices = new uint256[](candidateSourceCount);
    // Get valid oracle sources
    uint256 validSourceCount = 0;
    for (uint256 idx = 0; idx < candidateSourceCount; idx++) {
      try primarySources[token0][token1][idx].getPrice(token0, token1) returns (uint256 price, uint256 lastUpdate) {
        if (lastUpdate >= block.timestamp - maxPriceStales[token0][token1]) {
          prices[validSourceCount++] = price;
        }
      } catch {}
    }
    require(validSourceCount > 0, "OracleMedianizer::getPrice:: no valid source");
    // Sort prices (asc)
    for (uint256 i = 0; i < validSourceCount - 1; i++) {
      for (uint256 j = 0; j < validSourceCount - i - 1; j++) {
        if (prices[j] > prices[j + 1]) {
          (prices[j], prices[j + 1]) = (prices[j + 1], prices[j]);
        }
      }
    }
    uint256 maxPriceDeviation = maxPriceDeviations[token0][token1];
    // Algo:
    // - 1 valid source --> return price
    // - 2 valid sources
    //     --> if the prices within deviation threshold, return average
    //     --> else revert
    // - 3 valid sources --> check deviation threshold of each pair
    //     --> if all within threshold, return median
    //     --> if one pair within threshold, return average of the pair
    if (validSourceCount == 1) return prices[0]; // if 1 valid source, return
    if (validSourceCount == 2) {
      require(
        (prices[1] * 1e18) / prices[0] <= maxPriceDeviation,
        "OracleMedianizer::getPrice:: too much deviation 2 valid sources"
      );
      return (prices[0] + prices[1]) / 2; // if 2 valid sources, return average
    }
    bool midP0P1Ok = (prices[1] * 1e18) / prices[0] <= maxPriceDeviation;
    bool midP1P2Ok = (prices[2] * 1e18) / prices[1] <= maxPriceDeviation;
    if (midP0P1Ok && midP1P2Ok) return prices[1]; // if 3 valid sources, and each pair is within thresh, return median
    if (midP0P1Ok) return (prices[0] + prices[1]) / 2; // return average of pair within thresh
    if (midP1P2Ok) return (prices[1] + prices[2]) / 2; // return average of pair within thresh
    revert("OracleMedianizer::getPrice:: too much deviation 3 valid sources");
  }

  /// @dev Return the price of token0/token1, multiplied by 1e18
  function getPrice(address token0, address token1) external view override returns (uint256, uint256) {
    return (_getPrice(token0, token1), block.timestamp);
  }
}
