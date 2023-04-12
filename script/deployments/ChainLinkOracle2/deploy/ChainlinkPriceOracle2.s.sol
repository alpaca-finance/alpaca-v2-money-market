// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployChainlinkPriceOracle2Script is BaseScript {
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

    bytes memory _logicBytecode = abi.encodePacked(
      vm.getCode("./script/deployments/ChainLinkOracle2/deploy/ChainlinkPriceOracle2.json")
    );

    bytes memory data = abi.encodeWithSelector(bytes4(keccak256("initialize()")));

    address _chainLinkPriceOracle2Implementation;
    _startDeployerBroadcast();

    // deploy implementation
    assembly {
      _chainLinkPriceOracle2Implementation := create(0, add(_logicBytecode, 0x20), mload(_logicBytecode))
      if iszero(extcodesize(_chainLinkPriceOracle2Implementation)) {
        revert(0, 0)
      }
    }

    // deploy proxy
    address proxy = address(
      new TransparentUpgradeableProxy(_chainLinkPriceOracle2Implementation, proxyAdminAddress, data)
    );
    _stopBroadcast();

    console.log("_chainLinkPriceOracle2Implementation", _chainLinkPriceOracle2Implementation);
    console.log("_chainLinkPriceOracle2Proxy", proxy);
  }
}
