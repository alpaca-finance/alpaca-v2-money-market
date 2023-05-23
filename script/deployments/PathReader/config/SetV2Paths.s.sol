// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { IUniSwapV2PathReader } from "solidity/contracts/reader/interfaces/IUniSwapV2PathReader.sol";

contract SetV2PathsScript is BaseScript {
  using stdJson for string;

  IUniSwapV2PathReader.PathParams[] paths;
  address router;

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

    // Setup router
    router = pancakeswapRouterV2;

    // ********* WBNB ********* //
    // WBNB -> HIGH:
    _addLiquidationPath(wbnb, busd, high);

    // ********* USDC ********* //
    // USDC -> HIGH:
    _addLiquidationPath(usdc, busd, high);

    // ********* USDT ********* //
    // USDT -> HIGH:
    _addLiquidationPath(usdt, busd, high);

    // ********* BUSD ********* //
    // BUSD -> HIGH:
    _addLiquidationPath(busd, high);

    // ********* BTCB ********* //
    // BTCB -> HIGH:
    _addLiquidationPath(btcb, busd, high);

    // ********* ETH ********* //
    // ETH -> HIGH:
    _addLiquidationPath(eth, busd, high);

    // ********* CAKE ********* //
    // CAKE -> HIGH:
    _addLiquidationPath(cake, busd, high);

    // ********* XRP ********* //
    // XRP -> HIGH:
    _addLiquidationPath(xrp, busd, high);

    // ********* HIGH ********* //
    // HIGH -> BUSD:
    _addLiquidationPath(high, busd);

    _startDeployerBroadcast();

    IUniSwapV2PathReader(uniswapV2LikePathReader).setPaths(paths);

    _stopBroadcast();
  }

  function _addLiquidationPath(address _token1, address _token2) internal {
    address[] memory path = new address[](2);
    path[0] = _token1;
    path[1] = _token2;

    IUniSwapV2PathReader.PathParams memory _input = IUniSwapV2PathReader.PathParams({ router: router, path: path });

    paths.push(_input);
  }

  function _addLiquidationPath(
    address _token1,
    address _token2,
    address _token3
  ) internal {
    address[] memory path = new address[](3);
    path[0] = _token1;
    path[1] = _token2;
    path[2] = _token3;

    IUniSwapV2PathReader.PathParams memory _input = IUniSwapV2PathReader.PathParams({ router: router, path: path });

    paths.push(_input);
  }
}
