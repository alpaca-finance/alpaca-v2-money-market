// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../BaseScript.sol";

import { FlashLoanRepurchaser } from "solidity/contracts/repurchaser/FlashLoanRepurchaser.sol";

contract DeployRepurchaserScript is BaseScript {
  using stdJson for string;

  function run() public {
    _loadAddresses();

    _startDeployerBroadcast();

    address repurchaser = address(new FlashLoanRepurchaser(userAddress, address(moneyMarket), address(accountManager)));

    _stopBroadcast();

    _writeJson(vm.toString(repurchaser), ".repurchaser");
  }
}
