// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { LibMoneyMarket01 } from "solidity/contracts/money-market/libraries/LibMoneyMarket01.sol";

/// @title A HelperFacet for faciliating test
contract TestHelperFacet {
  function writeGlobalDebts(address _token, uint256 _newAmount) public {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    moneyMarketDs.globalDebts[_token] = _newAmount;
  }

  function writeoverCollatDebtValues(address _token, uint256 _newAmount) public {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    moneyMarketDs.overCollatDebtValues[_token] = _newAmount;
  }
}
