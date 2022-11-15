// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script, console } from "solidity/tests/utils/Script.sol";
import { SimplePriceOracle } from "solidity/contracts/oracle/SimplePriceOracle.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract MyScript is Script {
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

    _deployContract(vm.addr(deployerPrivateKey));
  }

  function _deployContract(address deployer) internal {
    address proxyAdmin = address(0x5379F32C8D5F663EACb61eeF63F722950294f452);
    address alpacaDeployer = address(0xC44f82b07Ab3E691F826951a6E335E1bC1bB0B51);

    if (alpacaDeployer == deployer) {
      vm.startBroadcast(deployer);
    } else {
      vm.startBroadcast();
    }

    SimplePriceOracle simplePriceOracle = new SimplePriceOracle();

    vm.stopBroadcast();
  }
}
