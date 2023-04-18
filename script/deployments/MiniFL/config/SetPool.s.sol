// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

contract SetPoolScript is BaseScript {
  using stdJson for string;

  struct SetPoolInput {
    uint256 pid;
    uint256 allocPoint;
  }

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

    SetPoolInput[] memory _setPoolInput = new SetPoolInput[](10);

    _setPoolInput[0] = SetPoolInput({ pid: 1, allocPoint: 0 });
    _setPoolInput[1] = SetPoolInput({ pid: 2, allocPoint: 100 });
    _setPoolInput[2] = SetPoolInput({ pid: 3, allocPoint: 300 });
    _setPoolInput[3] = SetPoolInput({ pid: 4, allocPoint: 200 });
    _setPoolInput[4] = SetPoolInput({ pid: 5, allocPoint: 400 });
    _setPoolInput[5] = SetPoolInput({ pid: 6, allocPoint: 0 });
    _setPoolInput[6] = SetPoolInput({ pid: 7, allocPoint: 250 });
    _setPoolInput[7] = SetPoolInput({ pid: 8, allocPoint: 350 });
    _setPoolInput[8] = SetPoolInput({ pid: 9, allocPoint: 150 });
    _setPoolInput[9] = SetPoolInput({ pid: 10, allocPoint: 50 });

    //---- execution ----//
    _startDeployerBroadcast();

    for (uint256 i; i < _setPoolInput.length; i++) {
      miniFL.setPool(_setPoolInput[i].pid, _setPoolInput[i].allocPoint, false);
    }

    _stopBroadcast();
  }
}
