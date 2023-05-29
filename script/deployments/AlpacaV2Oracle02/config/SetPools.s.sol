// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

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
    // WBNB-USDT fee 0.05
    addPCSV3PoolAddress(wbnb, usdt, 500);
    // USDC-USDT fee 0.01
    addPCSV3PoolAddress(usdc, usdt, 100);
    // BUSD-USDT fee 0.01
    addPCSV3PoolAddress(busd, usdt, 100);
    // BTCB-USDT fee 0.05
    addPCSV3PoolAddress(btcb, usdt, 500);

    //---- execution ----//
    _startDeployerBroadcast();
    alpacaV2Oracle02.setPools(v3Pools);
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
