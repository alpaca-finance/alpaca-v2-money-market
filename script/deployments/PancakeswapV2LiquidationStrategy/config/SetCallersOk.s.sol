pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { ILiquidationStrategy } from "solidity/contracts/money-market/interfaces/ILiquidationStrategy.sol";

contract SetLiquidatorsOkScript is BaseScript {
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
    bool isOk = true;
    address[] memory _callers = new address[](1);
    _callers[0] = address(moneyMarket);

    address[] memory _strats = new address[](2);
    _strats[0] = address(pancakeswapV2LiquidateStrat);
    _strats[1] = address(pancakeswapV2IbLiquidateStrat);

    _startDeployerBroadcast();

    for (uint8 i; i < _strats.length; i++) {
      ILiquidationStrategy(_strats[i]).setCallersOk(_callers, isOk);
    }

    _stopBroadcast();
  }
}
