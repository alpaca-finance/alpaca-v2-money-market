// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { SwapHelperIbLiquidationStrategy } from "solidity/contracts/money-market/SwapHelperIbLiquidationStrategy.sol";

contract DeploySwapHelperIbLiquidationStrategyScript is BaseScript {
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

    address _swapHelper = address(swapHelper);
    address _moneyMarket = address(moneyMarket);

    _startDeployerBroadcast();

    address swapHelperIbLiquidationStrategy = address(new SwapHelperIbLiquidationStrategy(_swapHelper, _moneyMarket));

    _stopBroadcast();

    _writeJson(vm.toString(swapHelperIbLiquidationStrategy), ".sharedStrategies.strategySwapHelperLiquidateIb");
  }
}
