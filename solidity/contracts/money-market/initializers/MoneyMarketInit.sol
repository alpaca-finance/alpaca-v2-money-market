// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";

contract MoneyMarketInit {
  function init() external {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage ds = LibMoneyMarket01.moneyMarketDiamondStorage();
  }
}
