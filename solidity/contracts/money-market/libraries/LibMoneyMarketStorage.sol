// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

library LibMoneyMarketStorage {
  // keccak256("moneymarket.diamond.storage");
  bytes32 internal constant MONEY_MARKET_STORAGE_POSITION =
    0x2758c6926500ec9dc8ab8cea4053d172d4f50d9b78a6c2ee56aa5dd18d2c800b;

  // Storage
  struct MoneyMarketDiamondStorage {
    // temp: map token => user => shapre
    mapping(address => mapping(address => uint256)) userShareMap;
  }

  function moneyMarketDiamondStorage()
    internal
    pure
    returns (MoneyMarketDiamondStorage storage moneyMarketStorage)
  {
    assembly {
      moneyMarketStorage.slot := MONEY_MARKET_STORAGE_POSITION
    }
  }
}
