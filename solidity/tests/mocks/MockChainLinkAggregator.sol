// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IAggregatorV3 } from "../../contracts/oracle/interfaces/IAggregatorV3.sol";

contract MockChainLinkAggregator is IAggregatorV3 {
  int256 price;
  uint8 decimal;

  constructor(int256 _price, uint8 _decimal) {
    price = _price;
    decimal = _decimal;
  }

  function decimals() external view returns (uint8) {
    return decimal;
  }

  function description() external pure returns (string memory) {
    return "description";
  }

  function version() external pure returns (uint256) {
    return 1;
  }

  function getRoundData(
    uint80 /*_roundId*/
  )
    external
    view
    returns (
      uint80,
      int256,
      uint256,
      uint256,
      uint80
    )
  {
    return (uint80(0), price, uint256(0), block.timestamp, uint80(0));
  }

  function latestRoundData()
    external
    view
    returns (
      uint80,
      int256,
      uint256,
      uint256,
      uint80
    )
  {
    return (uint80(0), price, uint256(0), block.timestamp, uint80(0));
  }
}
