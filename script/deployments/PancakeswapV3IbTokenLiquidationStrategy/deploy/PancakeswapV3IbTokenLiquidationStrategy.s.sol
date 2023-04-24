// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { PancakeswapV3IbTokenLiquidationStrategy } from "solidity/contracts/money-market/PancakeswapV3IbTokenLiquidationStrategy.sol";

contract DeployPancakeswapV3IbTokenLiquidationStrategyScript is BaseScript {
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

    address _routerV3 = address(pancakeswapRouterV3);
    address _moneyMarket = address(moneyMarket);

    _startDeployerBroadcast();

    address pancakeswapV2IbTokenLiquidationStrategy = address(
      new PancakeswapV3IbTokenLiquidationStrategy(_routerV3, _moneyMarket)
    );
    _stopBroadcast();

    _writeJson(
      vm.toString(pancakeswapV2IbTokenLiquidationStrategy),
      ".sharedStrategies.pancakeswap.strategyLiquidateIbV3"
    );
  }
}
