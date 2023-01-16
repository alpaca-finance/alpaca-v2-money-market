// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibDiamond } from "../libraries/LibDiamond.sol";

contract MoneyMarketInit {
  error MoneyMarketInit_InvalidAddress();
  error MoneyMarketInit_Initialized();

  function init(address _wNativeToken, address _wNativeRelayer) external {
    LibDiamond.DiamondStorage storage diamondDs = LibDiamond.diamondStorage();
    if (diamondDs.moneyMarketInitialized != 0) revert MoneyMarketInit_Initialized();
    LibMoneyMarket01.MoneyMarketDiamondStorage storage ds = LibMoneyMarket01.moneyMarketDiamondStorage();
    if (_wNativeToken == address(0) || _wNativeRelayer == address(0)) revert MoneyMarketInit_InvalidAddress();
    ds.wNativeToken = _wNativeToken;
    ds.wNativeRelayer = _wNativeRelayer;
    diamondDs.moneyMarketInitialized = 1;
  }
}
