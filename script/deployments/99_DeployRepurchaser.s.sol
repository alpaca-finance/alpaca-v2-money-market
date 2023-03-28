// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../BaseScript.sol";

import { PancakeV2FlashLoanRepurchaser } from "solidity/contracts/repurchaser/PancakeV2FlashLoanRepurchaser.sol";

contract DeployRepurchaserScript is BaseScript {
  using stdJson for string;

  function run() public {
    _loadAddresses();

    _startDeployerBroadcast();

    address repurchaser = address(
      new PancakeV2FlashLoanRepurchaser(
        userAddress,
        address(moneyMarket),
        address(accountManager),
        0x10ED43C718714eb63d5aA57B78B54704E256024E
      )
    );

    _stopBroadcast();

    _writeJson(vm.toString(repurchaser), ".repurchaser.pancakeV2");
  }
}
