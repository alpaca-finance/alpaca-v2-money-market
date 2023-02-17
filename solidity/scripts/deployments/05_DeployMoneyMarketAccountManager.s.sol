// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "../BaseScript.sol";

import { MoneyMarketAccountManager } from "solidity/contracts/account-manager/MoneyMarketAccountManager.sol";

contract DeployMoneyMarketAccountManagerScript is BaseScript {
  using stdJson for string;

  function run() public {
    _loadAddresses();

    _startDeployerBroadcast();

    address accountManager = address(new MoneyMarketAccountManager(address(moneyMarket)));

    // set account manager to allow interactions
    address[] memory _accountManagers = new address[](1);
    _accountManagers[0] = address(accountManager);

    moneyMarket.setAccountManagersOk(_accountManagers, true);

    _stopBroadcast();

    _writeJson(vm.toString(accountManager), ".moneyMarket.accountManager");
  }
}
