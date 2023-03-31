pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { PancakeswapV2IbTokenLiquidationStrategy } from "solidity/contracts/money-market/PancakeswapV2IbTokenLiquidationStrategy.sol";

contract DeployPancakeswapV2IbTokenLiquidationStrategyScript is BaseScript {
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

    address _router = address(pancakeswapV2Router);
    address _moneyMarket = address(moneyMarket);

    _startDeployerBroadcast();
    // deploy implementation
    address pancakeswapV2IbTokenLiquidationStrategy = address(
      new PancakeswapV2IbTokenLiquidationStrategy(_router, _moneyMarket)
    );
    _stopBroadcast();

    _writeJson(vm.toString(pancakeswapV2IbTokenLiquidationStrategy), ".sharedStrategies.pancakeswap.strategyLiquidate");
  }
}
