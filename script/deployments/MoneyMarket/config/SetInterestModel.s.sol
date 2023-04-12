// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

contract SetInterestModelScript is BaseScript {
  using stdJson for string;

  struct SetInterestModelInput {
    address token;
    address interestModel;
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

    SetInterestModelInput[2] memory _input = [
      SetInterestModelInput({ token: cake, interestModel: 0xc51d25a2C2d49eE2508B822829d43b9961deCB44 }),
      SetInterestModelInput({ token: dot, interestModel: 0xc51d25a2C2d49eE2508B822829d43b9961deCB44 })
    ];

    //---- execution ----//
    _startDeployerBroadcast();

    for (uint256 _i; _i < _input.length; _i++) {
      address token = _input[_i].token;
      address interestModel = _input[_i].interestModel;

      moneyMarket.setInterestModel(token, interestModel);
    }

    _stopBroadcast();
  }
}
