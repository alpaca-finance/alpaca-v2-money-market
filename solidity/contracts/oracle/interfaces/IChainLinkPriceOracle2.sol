// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import { IAggregatorV3 } from "./IAggregatorV3.sol";

interface IChainLinkPriceOracle2 {
  function setPriceFeeds(
    address[] calldata token0s,
    address[] calldata token1s,
    IAggregatorV3[][] calldata allSources
  ) external;

  function getPrice(address token0, address token1) external returns (uint256, uint256);
}
