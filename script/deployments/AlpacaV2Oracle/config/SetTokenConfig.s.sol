// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { IAlpacaV2Oracle } from "solidity/contracts/oracle/interfaces/IAlpacaV2Oracle.sol";

contract SetTokenConfigScript is BaseScript {
  using stdJson for string;

  address[] tokens;
  IAlpacaV2Oracle.Config[] configs;

  struct SetTokenConfigInput {
    address[] path;
    address router;
    uint64 maxPriceDiffBps;
    bool isUsingV3Pool;
  }

  address[] tokenPath;

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
    address[] memory _path;

    _path = new address[](2);
    _path[0] = cake;
    _path[1] = busd;
    addSetTokenConfigList(
      SetTokenConfigInput({ path: _path, router: pancakeswapV2Router, maxPriceDiffBps: 10500, isUsingV3Pool: false })
    );

    //---- execution ----//
    _startDeployerBroadcast();
    alpacaV2Oracle.setTokenConfig(tokens, configs);
    _stopBroadcast();
  }

  function addSetTokenConfigList(SetTokenConfigInput memory _input) internal {
    IAlpacaV2Oracle.Config memory config = IAlpacaV2Oracle.Config({
      router: _input.router,
      maxPriceDiffBps: _input.maxPriceDiffBps,
      path: _input.path,
      isUsingV3Pool: _input.isUsingV3Pool
    });

    tokens.push(_input.path[0]);
    configs.push(config);
  }
}
