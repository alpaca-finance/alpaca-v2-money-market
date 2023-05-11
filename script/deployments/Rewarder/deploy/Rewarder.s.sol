// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { Rewarder } from "solidity/contracts/miniFL/Rewarder.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployRewarderScript is BaseScript {
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

    string memory name = "HIGH Street";
    address miniFL = address(miniFL);
    address rewardToken = 0x5f4Bde007Dc06b867f86EBFE4802e34A1fFEEd63;
    uint256 maxRewardPerSecond = 1 ether;

    bytes memory data = abi.encodeWithSelector(
      bytes4(keccak256("initialize(string,address,address,uint256)")),
      name,
      miniFL,
      rewardToken,
      maxRewardPerSecond
    );

    _startDeployerBroadcast();
    // deploy implementation
    address rewarderImplementation = address(new Rewarder());
    // deploy proxy
    address proxy = address(new TransparentUpgradeableProxy(rewarderImplementation, proxyAdminAddress, data));

    console.log("rewarder", proxy);
    _stopBroadcast();
  }
}
