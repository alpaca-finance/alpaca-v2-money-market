// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { MMFlatSlopeModel2 } from "solidity/contracts/money-market/interest-models/MMFlatSlopeModel2.sol";

contract DeployMMFlatSlopeModel2Script is BaseScript {
  using stdJson for string;

  function run() public {
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
    address interestModel = address(new MMFlatSlopeModel2());
    _stopBroadcast();

    _writeJson(vm.toString(interestModel), ".sharedConfig.flatSlope2");
  }
}
