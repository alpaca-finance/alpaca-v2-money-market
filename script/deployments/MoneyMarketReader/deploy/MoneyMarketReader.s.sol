// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { MoneyMarketReader } from "solidity/contracts/reader/MoneyMarketReader.sol";

contract DeployMoneyMarketReaderScript is BaseScript {
  using stdJson for string;

  function run() public {
    _loadAddresses();

    /*
  ░██╗░░░░░░░██╗░█████╗░██████╗░███╗░░██╗██╗███╗░░██╗░██████╗░
  ░██║░░██╗░░██║██╔══██╗██╔══██╗████╗░██║██║████╗░██║██╔════╝░
  ░╚██╗████╗██╔╝███████║██████╔╝██╔██╗██║██║██╔██╗██║██║░░██╗░
  ░░████╔═████║░██╔══██║██╔══██╗██║╚████║██║██║╚████║██║░░╚██╗
  ░░╚██╔╝░╚██╔╝░██║░░██║██║░░██║██║░╚███║██║██║░╚███║╚██████╔╝
  ░░░╚═╝░░░╚═╝░░╚═╝░░╚═╝╚═╝░░╚═╝╚═╝░░╚══╝╚═╝╚═╝░░╚══╝░╚═════╝░
  Check all variables below before execute the deployment script
    */

    address _moneyMarket = address(moneyMarket);
    address _accountManager = address(accountManager);

    _startDeployerBroadcast();

    address mmReader = address(new MoneyMarketReader(_moneyMarket, _accountManager));

    _stopBroadcast();

    _writeJson(vm.toString(mmReader), ".moneyMarket.reader");
  }
}
