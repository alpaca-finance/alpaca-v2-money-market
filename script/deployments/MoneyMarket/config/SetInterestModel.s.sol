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
    _loadAddresses();
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
      SetInterestModelInput({ token: address(0), interestModel: address(0) }),
      SetInterestModelInput({ token: address(0), interestModel: address(0) })
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
