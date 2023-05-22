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

    string memory name = "high";
    address _miniFL = address(miniFL);
    address rewardToken = high;
    uint256 maxRewardPerSecond = 1 ether;

    bytes memory data = abi.encodeWithSelector(
      bytes4(keccak256("initialize(string,address,address,uint256)")),
      name,
      _miniFL,
      rewardToken,
      maxRewardPerSecond
    );

    _startDeployerBroadcast();
    // deploy implementation
    address rewarderImplementation = address(new Rewarder());
    // deploy proxy
    address proxy = address(new TransparentUpgradeableProxy(rewarderImplementation, proxyAdminAddress, data));

    writeRewarderToJson(proxy);

    _stopBroadcast();
  }

  function writeRewarderToJson(address _rewarder) internal {
    string[] memory cmds = new string[](9);
    cmds[0] = "npx";
    cmds[1] = "ts-node";
    cmds[2] = "./type-script/scripts/write-rewarder.ts";
    cmds[3] = "--name";
    cmds[4] = Rewarder(_rewarder).name();
    cmds[5] = "--address";
    cmds[6] = vm.toString(_rewarder);
    cmds[7] = "--rewardToken";
    cmds[8] = vm.toString(Rewarder(_rewarder).rewardToken());

    vm.ffi(cmds);
  }
}
