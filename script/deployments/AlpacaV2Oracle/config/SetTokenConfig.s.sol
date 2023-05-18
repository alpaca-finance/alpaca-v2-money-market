// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { IAlpacaV2Oracle } from "solidity/contracts/oracle/interfaces/IAlpacaV2Oracle.sol";

contract SetTokenConfigScript is BaseScript {
  using stdJson for string;

  address[] tokens;
  IAlpacaV2Oracle.Config[] configs;

  address[] alpacaGuardPath;

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

    // HIGH
    alpacaGuardPath.push(high);
    alpacaGuardPath.push(busd);
    alpacaGuardPath.push(usdt);
    addSetTokenConfigList(
      IAlpacaV2Oracle.Config({
        path: alpacaGuardPath,
        router: pancakeswapRouterV2,
        maxPriceDiffBps: 10500,
        isUsingV3Pool: false
      })
    );

    //---- execution ----//
    _startDeployerBroadcast();
    alpacaV2Oracle.setTokenConfig(tokens, configs);
    _stopBroadcast();
  }

  function addSetTokenConfigList(IAlpacaV2Oracle.Config memory _config) internal {
    tokens.push(_config.path[0]);
    configs.push(_config);

    delete alpacaGuardPath;
  }
}
