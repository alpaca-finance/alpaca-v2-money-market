// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../BaseScript.sol";

import { MoneyMarketReader } from "solidity/contracts/reader/MoneyMarketReader.sol";

contract DeployMoneyMarketReaderScript is BaseScript {
  using stdJson for string;

  function run() public {
    _startDeployerBroadcast();

    address mmReader = address(new MoneyMarketReader(address(moneyMarket), address(accountManager)));

    _stopBroadcast();

    // moneyMarket.reader = address
    _writeJson(vm.toString(mmReader), ".moneyMarket.reader");
  }
}
