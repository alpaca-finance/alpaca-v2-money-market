pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { MiniFL } from "solidity/contracts/miniFL/MiniFL.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployMiniFLScript is BaseScript {
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

    address ALPACA = alpaca;
    uint256 maxAlpacaPerSecond = 1 ether;

    bytes memory data = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,uint256)")),
      ALPACA,
      maxAlpacaPerSecond
    );

    _startDeployerBroadcast();
    // deploy implementation
    address miniFLImplementation = address(new MiniFL());
    // deploy proxy
    address proxy = address(new TransparentUpgradeableProxy(miniFLImplementation, proxyAdminAddress, data));

    _stopBroadcast();

    _writeJson(vm.toString(miniFLImplementation), ".miniFL.implementation");
    _writeJson(vm.toString(proxy), ".miniFL.proxy");
  }
}
