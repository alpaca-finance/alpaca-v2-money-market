// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { AlpacaV2Oracle } from "solidity/contracts/oracle/AlpacaV2Oracle.sol";
import { IAlpacaV2Oracle } from "solidity/contracts/oracle/interfaces/IAlpacaV2Oracle.sol";

contract SetTokenConfigScript is BaseScript {
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

    // set alpaca guard path
    uint8 configLength = 3;
    address[] memory tokens = new address[](configLength);
    IAlpacaV2Oracle.Config[] memory configs = new IAlpacaV2Oracle.Config[](configLength);

    address[] memory path;
    // WBNB
    path = new address[](2);
    path[0] = wbnb;
    path[1] = busd;

    tokens[0] = wbnb;
    configs[0] = IAlpacaV2Oracle.Config({ router: pancakeswapV2Router, maxPriceDiffBps: 10500, path: path });

    // ALPACA
    path = new address[](2);
    path[0] = alpaca;
    path[1] = busd;

    tokens[1] = alpaca;
    configs[1] = IAlpacaV2Oracle.Config({ router: pancakeswapV2Router, maxPriceDiffBps: 10500, path: path });

    // CAKE
    path = new address[](2);
    path[0] = cake;
    path[1] = busd;

    tokens[2] = cake;
    configs[2] = IAlpacaV2Oracle.Config({ router: pancakeswapV2Router, maxPriceDiffBps: 10500, path: path });

    //---- execution ----//
    _startDeployerBroadcast();
    alpacaV2Oracle.setTokenConfig(tokens, configs);
    _stopBroadcast();
  }
}
