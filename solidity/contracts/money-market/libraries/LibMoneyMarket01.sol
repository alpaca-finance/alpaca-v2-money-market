// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LibDoublyLinkedList } from "./LibDoublyLinkedList.sol";

library LibMoneyMarket01 {
  // keccak256("moneymarket.diamond.storage");
  bytes32 internal constant MONEY_MARKET_STORAGE_POSITION =
    0x2758c6926500ec9dc8ab8cea4053d172d4f50d9b78a6c2ee56aa5dd18d2c800b;

  error LibMoneyMarket01_BadSubAccountId();

  // Storage
  struct MoneyMarketDiamondStorage {
    mapping(address => address) tokenToIbTokens;
    mapping(address => address) ibTokenToTokens;
    mapping(address => uint256) debtValues;
    mapping(address => uint256) debtShares;
    mapping(address => LibDoublyLinkedList.List) subAccountCollats;
    mapping(address => LibDoublyLinkedList.List) subAccountDebtShares;
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

  function getSubAccount(address primary, uint256 subAccountId)
    internal
    pure
    returns (address)
  {
    if (subAccountId > 255) revert LibMoneyMarket01_BadSubAccountId();
    return address(uint160(primary) ^ uint160(subAccountId));
  }

  // function debtValToShare(address _ibToken, address _debtVal) external {}
}
