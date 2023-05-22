// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { IRewarder } from "solidity/contracts/miniFL/interfaces/IRewarder.sol";

contract SetRewardPerSecondScript is BaseScript {
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

    IRewarder rewarder = IRewarder(0x527c87bDBEB012f9f27A75dC3D5CC3F0Dd51B3bB);
    uint256 _newRewardPerSecond = 6717096560846561;
    bool _withUpdate = true;

    //---- execution ----//
    _startDeployerBroadcast();

    rewarder.setRewardPerSecond(_newRewardPerSecond, _withUpdate);

    _stopBroadcast();
  }
}
