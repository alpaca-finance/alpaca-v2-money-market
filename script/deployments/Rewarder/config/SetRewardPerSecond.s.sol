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

    IRewarder rewarder = IRewarder(address(0));
    uint256 _newRewardPerSecond = 7676681783824641;
    bool _withUpdate = true;

    //---- execution ----//
    _startDeployerBroadcast();

    rewarder.setRewardPerSecond(_newRewardPerSecond, _withUpdate);

    _stopBroadcast();
  }
}
