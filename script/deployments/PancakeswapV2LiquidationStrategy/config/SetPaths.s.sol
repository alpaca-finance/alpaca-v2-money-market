// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { PancakeswapV2LiquidationStrategy } from "solidity/contracts/money-market/PancakeswapV2LiquidationStrategy.sol";

contract SetPathsScript is BaseScript {
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

    address[] memory _strats = new address[](2);
    _strats[0] = address(pancakeswapV2LiquidateStrat);
    _strats[1] = address(pancakeswapV2IbLiquidateStrat);

    address[] memory _wbnbLiquidationPath = new address[](2);
    _wbnbLiquidationPath[0] = wbnb;
    _wbnbLiquidationPath[1] = busd;

    PancakeswapV2LiquidationStrategy.SetPathParams[]
      memory _inputs = new PancakeswapV2LiquidationStrategy.SetPathParams[](1);

    _inputs[0].path = _wbnbLiquidationPath;

    _startDeployerBroadcast();

    for (uint8 i; i < _strats.length; i++) {
      PancakeswapV2LiquidationStrategy(_strats[i]).setPaths(_inputs);
    }

    _stopBroadcast();
  }
}
