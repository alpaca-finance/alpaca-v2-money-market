// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { IAlpacaV2Oracle } from "solidity/contracts/oracle/interfaces/IAlpacaV2Oracle.sol";

interface IPancakeSwapV3Factory {
  function getPool(
    address tokenA,
    address tokenB,
    uint24 fee
  ) external view returns (address pool);
}

contract SetPoolsScript is BaseScript {
  using stdJson for string;

  address[] v3Pools;

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

    // 2 hops
    // ETH-WBNB fee 0.25
    addPCSV3PoolAddress(eth, wbnb, 2500);

    // 1 hop
    // WBNB-BUSD fee 0.05
    addPCSV3PoolAddress(wbnb, busd, 500);
    // USDC-BUSD fee 0.01
    addPCSV3PoolAddress(usdc, busd, 100);
    // USDT-BUSD fee 0.01
    addPCSV3PoolAddress(usdt, busd, 100);
    // BTCB-BUSD fee 0.05
    addPCSV3PoolAddress(btcb, busd, 500);

    //---- execution ----//
    _startDeployerBroadcast();
    alpacaV2Oracle.setPools(v3Pools);
    _stopBroadcast();
  }

  function addPCSV3PoolAddress(
    address _tokenA,
    address _tokenB,
    uint24 _fee
  ) internal {
    address pool = IPancakeSwapV3Factory(pancakeswapFactoryV3).getPool(_tokenA, _tokenB, _fee);
    if (pool == address(0)) {
      revert("Pool not exist!");
    }
    v3Pools.push(pool);
  }
}
