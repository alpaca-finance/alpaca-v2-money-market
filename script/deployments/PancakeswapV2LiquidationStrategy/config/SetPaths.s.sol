// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { PancakeswapV2LiquidationStrategy } from "solidity/contracts/money-market/PancakeswapV2LiquidationStrategy.sol";

contract SetPathsScript is BaseScript {
  using stdJson for string;

  PancakeswapV2LiquidationStrategy.SetPathParams[] liquidationPaths;

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

    address[] memory _strats = new address[](1);
    _strats[0] = address(pancakeswapV2IbLiquidateStrat);

    // ********* CAKE ********* //
    // CAKE -> HIGH:
    setLiquidationPath(cake, busd, high);

    // ********* XRP ********* //
    // XRP -> HIGH:
    setLiquidationPath(xrp, busd, high);

    _startDeployerBroadcast();

    for (uint8 i; i < _strats.length; i++) {
      PancakeswapV2LiquidationStrategy(_strats[i]).setPaths(liquidationPaths);
    }

    _stopBroadcast();
  }

  function setLiquidationPath(address _token1, address _token2) internal {
    address[] memory path = new address[](2);
    path[0] = _token1;
    path[1] = _token2;

    PancakeswapV2LiquidationStrategy.SetPathParams memory _input = PancakeswapV2LiquidationStrategy.SetPathParams({
      path: path
    });

    liquidationPaths.push(_input);
  }

  function setLiquidationPath(
    address _token1,
    address _token2,
    address _token3
  ) internal {
    address[] memory path = new address[](3);
    path[0] = _token1;
    path[1] = _token2;
    path[2] = _token3;

    PancakeswapV2LiquidationStrategy.SetPathParams memory _input = PancakeswapV2LiquidationStrategy.SetPathParams({
      path: path
    });

    liquidationPaths.push(_input);
  }
}
