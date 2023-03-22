// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../BaseScript.sol";

import { MiniFL } from "solidity/contracts/miniFL/MiniFL.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployMiniFLScript is BaseScript {
  using stdJson for string;

  function run() public {
    _loadAddresses();

    _startDeployerBroadcast();

    // deploy implementation
    address miniFLImplementation = address(new MiniFL());

    // deploy proxy
    address ALPACA = 0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F;
    uint256 maxAlpacaPerSecond = 1 ether;
    bytes memory data = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,uint256)")),
      ALPACA,
      maxAlpacaPerSecond
    );
    address proxy = address(new TransparentUpgradeableProxy(miniFLImplementation, proxyAdminAddress, data));

    _stopBroadcast();

    _writeJson(vm.toString(miniFLImplementation), ".miniFL.implementation");
    _writeJson(vm.toString(proxy), ".miniFL.proxy");
  }
}
