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

    SetInterestModelInput[5] memory _input = [
      SetInterestModelInput({ token: cake, interestModel: 0xd41cA0E6C44fACBf30c97CD99aeC2Fa4FdCe7a3C }),
      SetInterestModelInput({ token: dot, interestModel: 0xd41cA0E6C44fACBf30c97CD99aeC2Fa4FdCe7a3C }),
      SetInterestModelInput({ token: alpaca, interestModel: 0xd41cA0E6C44fACBf30c97CD99aeC2Fa4FdCe7a3C }),
      SetInterestModelInput({ token: busd, interestModel: 0xd41cA0E6C44fACBf30c97CD99aeC2Fa4FdCe7a3C }),
      SetInterestModelInput({ token: wbnb, interestModel: 0xd41cA0E6C44fACBf30c97CD99aeC2Fa4FdCe7a3C })
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
