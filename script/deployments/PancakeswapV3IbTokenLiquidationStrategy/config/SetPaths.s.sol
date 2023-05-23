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
    bytes memory liquidationPath;

    // ********* WBNB ********* //
    // WBNB -> CAKE:
    liquidationPath = encodePath(wbnb, 2500, cake);
    setLiquidationPath(liquidationPath);
    // WBNB -> XRP:
    liquidationPath = encodePath(wbnb, 2500, xrp);
    setLiquidationPath(liquidationPath);

    // ********* USDC ********* //
    // USDC -> CAKE:
    liquidationPath = encodePath(usdc, 100, usdt, 2500, cake);
    setLiquidationPath(liquidationPath);
    // USDC -> XRP:
    liquidationPath = encodePath(usdc, 100, usdt, 500, wbnb, 2500, xrp);
    setLiquidationPath(liquidationPath);

    // ********* USDT ********* //
    // USDT -> CAKE:
    liquidationPath = encodePath(usdt, 100, wbnb, 2500, cake);
    setLiquidationPath(liquidationPath);
    // USDT -> XRP:
    liquidationPath = encodePath(usdt, 100, wbnb, 2500, xrp);
    setLiquidationPath(liquidationPath);

    // ********* BUSD ********* //
    // BUSD -> CAKE:
    liquidationPath = encodePath(busd, 500, wbnb, 2500, cake);
    setLiquidationPath(liquidationPath);
    // BUSD -> XRP:
    liquidationPath = encodePath(busd, 500, wbnb, 2500, xrp);
    setLiquidationPath(liquidationPath);

    // ********* BTCB ********* //
    // BTCB -> CAKE
    liquidationPath = encodePath(btcb, 2500, wbnb, 2500, cake);
    setLiquidationPath(liquidationPath);
    // BTCB -> XRP
    liquidationPath = encodePath(btcb, 2500, wbnb, 2500, xrp);
    setLiquidationPath(liquidationPath);

    // ********* ETH ********* //
    // ETH -> CAKE
    liquidationPath = encodePath(eth, 2500, wbnb, 2500, cake);
    setLiquidationPath(liquidationPath);
    // ETH -> XRP
    liquidationPath = encodePath(eth, 2500, wbnb, 2500, xrp);
    setLiquidationPath(liquidationPath);

    // ********* CAKE ********* //
    // CAKE -> BTCB
    liquidationPath = encodePath(cake, 2500, usdt, 500, btcb);
    setLiquidationPath(liquidationPath);
    // CAKE -> WBNB
    liquidationPath = encodePath(cake, 2500, wbnb);
    setLiquidationPath(liquidationPath);
    // CAKE -> BUSD
    liquidationPath = encodePath(cake, 2500, usdt, 100, busd);
    setLiquidationPath(liquidationPath);
    // CAKE -> USDT
    liquidationPath = encodePath(cake, 2500, usdt);
    setLiquidationPath(liquidationPath);
    // CAKE -> USDC
    liquidationPath = encodePath(cake, 2500, usdt, 100, usdc);
    setLiquidationPath(liquidationPath);
    // CAKE -> XRP
    liquidationPath = encodePath(cake, 2500, wbnb, 2500, xrp);
    setLiquidationPath(liquidationPath);

    // ********* XRP ********* //
    // XRP -> BTCB
    liquidationPath = encodePath(xrp, 2500, wbnb, 2500, btcb);
    setLiquidationPath(liquidationPath);
    // XRP -> WBNB
    liquidationPath = encodePath(xrp, 2500, wbnb);
    setLiquidationPath(liquidationPath);
    // XRP -> BUSD
    liquidationPath = encodePath(xrp, 2500, wbnb, 500, busd);
    setLiquidationPath(liquidationPath);
    // XRP -> USDT
    liquidationPath = encodePath(xrp, 2500, wbnb, 100, usdt);
    setLiquidationPath(liquidationPath);
    // XRP -> USDC
    liquidationPath = encodePath(xrp, 2500, wbnb, 500, usdt, 100, usdc);
    setLiquidationPath(liquidationPath);
    // XRP -> CAKE
    liquidationPath = encodePath(xrp, 2500, wbnb, 2500, cake);
    setLiquidationPath(liquidationPath);

    //---- execution ----//
    _startDeployerBroadcast();

    for (uint8 i; i < _strats.length; i++) {
      PancakeswapV3IbTokenLiquidationStrategy(_strats[i]).setPaths(paths);
    }

    _stopBroadcast();
  }

  function encodePath(
    address _tokenA,
    uint24 _fee,
    address _tokenB
  ) internal pure returns (bytes memory pool) {
    pool = abi.encodePacked(_tokenA, _fee, _tokenB);
  }

  function encodePath(
    address _tokenA,
    uint24 _fee0,
    address _tokenB,
    uint24 _fee1,
    address _tokenC
  ) internal pure returns (bytes memory pool) {
    pool = abi.encodePacked(_tokenA, _fee0, _tokenB, _fee1, _tokenC);
  }

  function encodePath(
    address _tokenA,
    uint24 _fee0,
    address _tokenB,
    uint24 _fee1,
    address _tokenC,
    uint24 _fee2,
    address _tokenD
  ) internal pure returns (bytes memory pool) {
    pool = abi.encodePacked(_tokenA, _fee0, _tokenB, _fee1, _tokenC, _fee2, _tokenD);
  }

  function setLiquidationPath(bytes memory liquidationPath) internal {
    paths.push(liquidationPath);

    delete liquidationPath;
  }
}
