// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { OracleMedianizer } from "solidity/contracts/oracle/OracleMedianizer.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployOracleMedianizerScript is BaseScript {
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

    bytes memory data = abi.encodeWithSelector(bytes4(keccak256("initialize()")));

    _startDeployerBroadcast();
    // deploy implementation
    address oracleMedianizerImplementation = address(new OracleMedianizer());
    // deploy proxy
    address proxy = address(new TransparentUpgradeableProxy(oracleMedianizerImplementation, proxyAdminAddress, data));

    _stopBroadcast();

    _writeJson(vm.toString(proxy), ".oracleMedianizer");
  }
}
