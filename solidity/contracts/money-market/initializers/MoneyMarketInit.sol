// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";

contract MoneyMarketInit {
  error MoneyMarketInit_InvalidAddress();

  function init(address _nativeToken, address _nativeRelayer) external {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage ds = LibMoneyMarket01.moneyMarketDiamondStorage();
    if (_nativeToken == address(0) || _nativeRelayer == address(0)) revert MoneyMarketInit_InvalidAddress();
    // todo: should we add state here to mark contract is initilized
    ds.nativeToken = ds.nativeToken == address(0) ? _nativeToken : ds.nativeToken;
    ds.nativeRelayer = ds.nativeRelayer == address(0) ? _nativeRelayer : ds.nativeRelayer;
  }
}
