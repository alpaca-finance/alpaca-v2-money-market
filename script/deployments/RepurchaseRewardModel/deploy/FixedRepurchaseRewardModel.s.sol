// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { FixedFeeModel } from "solidity/contracts/money-market/fee-models/FixedFeeModel.sol";

contract DeployFixedRepurchaseRewardModelScript is BaseScript {
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

    _startDeployerBroadcast();
    // deploy implementation
    address fixedRepurchaseRewardModel = address(new FixedFeeModel());
    _stopBroadcast();

    _writeJson(vm.toString(fixedRepurchaseRewardModel), ".sharedConfig.fixedRepurchaseRewardModel");
  }
}
