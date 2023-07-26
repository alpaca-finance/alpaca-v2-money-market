// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

struct SetInterestModelInput {
  address token;
  address interestModel;
}

contract SetNonCollatInterestModelScript is BaseScript {
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

    bool isOk = true;
    address borrower = address(0);
    SetInterestModelInput[2] memory _input = [
      SetInterestModelInput({ token: usdt, interestModel: flatSlope1 }),
      SetInterestModelInput({ token: wbnb, interestModel: flatSlope1 })
    ];

    //---- execution ----//
    _startDeployerBroadcast();

    for (uint256 _i; _i < _input.length; _i++) {
      address token = _input[_i].token;
      address interestModel = _input[_i].interestModel;

      moneyMarket.setNonCollatInterestModel(borrower, token, interestModel);
    }
    _stopBroadcast();
  }
}
