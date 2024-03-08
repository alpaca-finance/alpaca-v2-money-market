// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseScript } from "script/BaseScript.sol";
import { MMFlatSlopeModel3 } from "solidity/contracts/money-market/interest-models/MMFlatSlopeModel3.sol";

contract DeployMMFlatSlopeModel3Script is BaseScript {
  function run() external {
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
    address interestModel = address(new MMFlatSlopeModel3());
    _stopBroadcast();

    _writeJson(vm.toString(interestModel), ".sharedConfig.flatSlope3");
  }
}
