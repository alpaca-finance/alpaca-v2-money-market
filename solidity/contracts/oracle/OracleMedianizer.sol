// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IOracleMedianizer } from "./interfaces/IOracleMedianizer.sol";
import { IPriceOracle } from "./interfaces/IPriceOracle.sol";

import { LibFullMath } from "./libraries/LibFullMath.sol";

contract OracleMedianizer is OwnableUpgradeable, IOracleMedianizer {
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

  // errors
  error OracleMedianizer_InconsistentLength();
  error OracleMedianizer_BadMaxDeviation();
  error OracleMedianizer_SourceLengthExceed();
  error OracleMedianizer_NoPrimarySource();
  error OracleMedianizer_NoValidSource();
  error OracleMedianizer_TooMuchDeviation();

  constructor() {
    _disableInitializers();
  }

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
    if (
      token0s.length != token1s.length ||
      token0s.length != allSources.length ||
      token0s.length != maxPriceDeviationList.length ||
      token0s.length != maxPriceStaleList.length
    ) revert OracleMedianizer_InconsistentLength();

    uint256 len = token0s.length;
    for (uint256 idx; idx < len; ) {
      _setPrimarySources(
        token0s[idx],
        token1s[idx],
        maxPriceDeviationList[idx],
        maxPriceStaleList[idx],
        allSources[idx]
      );
      unchecked {
        ++idx;
      }
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
    if (maxPriceDeviation > MAX_PRICE_DEVIATION || maxPriceDeviation < MIN_PRICE_DEVIATION)
      revert OracleMedianizer_BadMaxDeviation();

    uint256 sourceLength = sources.length;
    if (sourceLength > 3) revert OracleMedianizer_SourceLengthExceed();

    primarySourceCount[token0][token1] = sourceLength;
    primarySourceCount[token1][token0] = sourceLength;
    maxPriceDeviations[token0][token1] = maxPriceDeviation;
    maxPriceDeviations[token1][token0] = maxPriceDeviation;
    maxPriceStales[token0][token1] = maxPriceStale;
    maxPriceStales[token1][token0] = maxPriceStale;
    for (uint256 idx; idx < sourceLength; ) {
      primarySources[token0][token1][idx] = sources[idx];
      primarySources[token1][token0][idx] = sources[idx];
      unchecked {
        ++idx;
      }
    }
    emit SetPrimarySources(token0, token1, maxPriceDeviation, maxPriceStale, sources);
  }

  /// @dev Return token0/token1 price
  /// @param token0 Token0 to get price of
  /// @param token1 Token1 to get price of
  /// NOTE: Support at most 3 oracle sources per token
  function _getPrice(address token0, address token1) internal view returns (uint256) {
    uint256 candidateSourceCount = primarySourceCount[token0][token1];
    if (candidateSourceCount == 0) revert OracleMedianizer_NoPrimarySource();
    uint256[] memory prices = new uint256[](candidateSourceCount);
    // Get valid oracle sources
    uint256 validSourceCount;
    unchecked {
      for (uint256 idx; idx < candidateSourceCount; ++idx) {
        try primarySources[token0][token1][idx].getPrice(token0, token1) returns (uint256 price, uint256 lastUpdate) {
          if (lastUpdate >= block.timestamp - maxPriceStales[token0][token1]) {
            prices[validSourceCount++] = price;
          }
        } catch {}
      }
    }
    if (validSourceCount == 0) revert OracleMedianizer_NoValidSource();
    // Sort prices (asc)
    unchecked {
      uint256 iterationCount = validSourceCount - 1;
      for (uint256 _i; _i < iterationCount; ) {
        for (uint256 _j; _j < iterationCount - _i; ) {
          if (prices[_j] > prices[_j + 1]) {
            (prices[_j], prices[_j + 1]) = (prices[_j + 1], prices[_j]);
          }
          ++_j;
        }
        ++_i;
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
    bool midP0P1Ok = (prices[1] * 1e18) / prices[0] <= maxPriceDeviation;
    if (validSourceCount == 2) {
      if (!midP0P1Ok) revert OracleMedianizer_TooMuchDeviation();
      return (prices[0] + prices[1]) / 2; // if 2 valid sources, return average
    }
    bool midP1P2Ok = (prices[2] * 1e18) / prices[1] <= maxPriceDeviation;
    if (midP0P1Ok && midP1P2Ok) return prices[1]; // if 3 valid sources, and each pair is within thresh, return median
    if (midP0P1Ok) return (prices[0] + prices[1]) / 2; // return average of pair within thresh
    if (midP1P2Ok) return (prices[1] + prices[2]) / 2; // return average of pair within thresh
    revert OracleMedianizer_TooMuchDeviation();
  }

  /// @dev Return the price of token0/token1, multiplied by 1e18
  function getPrice(address token0, address token1) external view override returns (uint256, uint256) {
    return (_getPrice(token0, token1), block.timestamp);
  }
}
