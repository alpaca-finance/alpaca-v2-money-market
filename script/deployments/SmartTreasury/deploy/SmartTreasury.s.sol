// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";
import { SmartTreasury } from "solidity/contracts/smart-treasury/SmartTreasury.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeploySmartTreasuryScript is BaseScript {
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
    address smartTreasuryImplementation = address(new SmartTreasury());

    // deploy proxy
    bytes memory data = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address)")),
      address(swapHelper),
      oracleMedianizer
    );
    address smartTreasuryProxy = address(
      new TransparentUpgradeableProxy(smartTreasuryImplementation, proxyAdminAddress, data)
    );

    _stopBroadcast();

    _writeJson(vm.toString(smartTreasuryImplementation), ".smartTreasury.implementation");
    _writeJson(vm.toString(smartTreasuryProxy), ".smartTreasury.proxy");
  }
}
