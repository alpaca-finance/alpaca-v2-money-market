pragma solidity 0.8.17;

import { IPriceOracle } from "../../contracts/oracle/interfaces/IPriceOracle.sol";

contract MockChainLinkPriceOracle is IPriceOracle {
  struct PriceMapData {
    uint256 price;
    uint256 lastUpdated;
  }
  mapping(address => mapping(address => PriceMapData)) priceMap;

  constructor() {}

  function add(
    address t0,
    address t1,
    uint256 price,
    uint256 timestamp
  ) public {
    priceMap[t0][t1].price = price;
    priceMap[t0][t1].lastUpdated = timestamp;
  }

  function getPrice(address token0, address token1) external view returns (uint256, uint256) {
    return (priceMap[token0][token1].price, priceMap[token0][token1].lastUpdated);
  }
}
