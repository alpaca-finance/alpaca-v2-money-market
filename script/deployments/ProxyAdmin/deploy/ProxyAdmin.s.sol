// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract DeployProxyAdminScript is BaseScript {
  using stdJson for string;

  function run() public {
    _startDeployerBroadcast();

    address proxyAdmin = address(new ProxyAdmin());

    _stopBroadcast();

    // proxyAdmin = address
    _writeJson(vm.toString(proxyAdmin), ".proxyAdmin");
  }
}
