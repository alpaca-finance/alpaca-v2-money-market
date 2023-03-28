// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { AlpacaV2Oracle } from "solidity/contracts/oracle/AlpacaV2Oracle.sol";
import { IAlpacaV2Oracle } from "solidity/contracts/oracle/interfaces/IAlpacaV2Oracle.sol";

contract SetTokenConfigScript is BaseScript {
  using stdJson for string;

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

    // set alpaca guard path
    address[] memory tokens = new address[](1);
    tokens[0] = wbnb;

    IAlpacaV2Oracle.Config[] memory configs = new IAlpacaV2Oracle.Config[](1);
    address[] memory path;
    path = new address[](2);
    path[0] = wbnb;
    path[1] = busd;

    configs[0] = IAlpacaV2Oracle.Config({ router: pancakeswapV2Router, maxPriceDiffBps: 10500, path: path });

    _startDeployerBroadcast();
    alpacaV2Oracle.setTokenConfig(tokens, configs);
    _stopBroadcast();
  }
}
