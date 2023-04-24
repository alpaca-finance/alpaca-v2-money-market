// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { PancakeswapV3IbTokenLiquidationStrategy } from "solidity/contracts/money-market/PancakeswapV3IbTokenLiquidationStrategy.sol";

contract SetPathsScript is BaseScript {
  using stdJson for string;

  bytes[] paths;

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
    _strats[0] = address(pancakeswapV3IbLiquidateStrat);

    addPool(dot, 2500, wbnb);
    addPool(wbnb, 500, busd);

    //---- execution ----//
    _startDeployerBroadcast();

    for (uint8 i; i < _strats.length; i++) {
      PancakeswapV3IbTokenLiquidationStrategy(_strats[i]).setPaths(paths);
    }

    _stopBroadcast();
  }

  function encodePool(
    address _tokenA,
    uint24 _fee,
    address _tokenB
  ) internal pure returns (bytes memory pool) {
    pool = abi.encodePacked(_tokenA, _fee, _tokenB);
  }

  function addPool(
    address _tokenA,
    uint24 _fee,
    address _tokenB
  ) internal {
    paths.push(encodePool(_tokenA, _fee, _tokenB));
  }
}
