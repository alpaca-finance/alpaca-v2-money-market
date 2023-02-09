// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "./BaseDeploymentScript.sol";

import { MoneyMarketReader } from "solidity/contracts/reader/MoneyMarketReader.sol";

contract DeployMoneyMarketFacets is BaseDeploymentScript {
  using stdJson for string;

  function _run() internal override {
    _startDeployerBroadcast();

    // TODO
    address mmReader = address(new MoneyMarketReader(0x7Cd6B7f3Fb066D11eA35dF24Ab9Cdd58292ec352));

    _stopBroadcast();

    // moneyMarket.reader = address
    vm.toString(mmReader).write(configFilePath, ".moneyMarket.reader");
  }
}
