// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { IUniSwapV3PathReader } from "solidity/contracts/reader/interfaces/IUniSwapV3PathReader.sol";

contract SetPCSV3PathsScript is BaseScript {
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

    bytes memory path;

    // ********* WBNB ********* //
    // WBNB -> USDC:
    path = _encodePath(wbnb, 500, usdt, 100, usdc);
    _addPath(path);
    // WBNB -> USDT:
    path = _encodePath(wbnb, 500, usdt);
    _addPath(path);
    // WBNB -> BUSD:
    path = _encodePath(wbnb, 500, busd);
    _addPath(path);
    // WBNB -> BTCB:
    path = _encodePath(wbnb, 100, usdt, 500, btcb);
    _addPath(path);
    // WBNB -> ETH:
    path = _encodePath(wbnb, 2500, eth);
    _addPath(path);
    // WBNB -> CAKE:
    path = _encodePath(wbnb, 2500, cake);
    _addPath(path);
    // WBNB -> XRP:
    path = _encodePath(wbnb, 2500, xrp);
    _addPath(path);

    // ********* USDC ********* //
    // USDC -> BTCB:
    path = _encodePath(usdc, 100, usdt, 500, btcb);
    _addPath(path);
    // USDC -> ETH:
    path = _encodePath(usdc, 500, eth);
    _addPath(path);
    // USDC -> WBNB:
    path = _encodePath(usdc, 100, usdt, 500, wbnb);
    _addPath(path);
    // USDC -> BUSD:
    path = _encodePath(usdc, 100, busd);
    _addPath(path);
    // USDC -> USDT:
    path = _encodePath(usdc, 100, usdt);
    _addPath(path);
    // USDC -> CAKE:
    path = _encodePath(usdc, 100, usdt, 2500, cake);
    _addPath(path);
    // USDC -> XRP:
    path = _encodePath(usdc, 100, usdt, 500, wbnb, 2500, xrp);
    _addPath(path);

    // ********* USDT ********* //
    // USDT -> BTCB:
    path = _encodePath(usdt, 500, btcb);
    _addPath(path);
    // USDT -> ETH:
    path = _encodePath(usdt, 100, usdc, 500, eth);
    _addPath(path);
    // USDT -> WBNB:
    path = _encodePath(usdt, 100, wbnb);
    _addPath(path);
    // USDT -> BUSD:
    path = _encodePath(usdt, 100, busd);
    _addPath(path);
    // USDT -> USDC:
    path = _encodePath(usdt, 100, usdc);
    _addPath(path);
    // USDT -> CAKE:
    path = _encodePath(usdt, 2500, cake);
    _addPath(path);
    // USDT -> XRP:
    path = _encodePath(usdt, 100, wbnb, 2500, xrp);
    _addPath(path);

    // ********* BUSD ********* //
    // BUSD -> BTCB:
    path = _encodePath(busd, 500, btcb);
    _addPath(path);
    // BUSD -> ETH:
    path = _encodePath(busd, 100, usdc, 500, eth);
    _addPath(path);
    // BUSD -> WBNB:
    path = _encodePath(busd, 100, usdt, 100, wbnb);
    _addPath(path);
    // BUSD -> USDT:
    path = _encodePath(busd, 100, usdt);
    _addPath(path);
    // BUSD -> USDC:
    path = _encodePath(busd, 100, usdc);
    _addPath(path);
    // BUSD -> CAKE:
    path = _encodePath(busd, 2500, cake);
    _addPath(path);
    // BUSD -> XRP:
    path = _encodePath(busd, 500, wbnb, 2500, xrp);
    _addPath(path);

    // ********* BTCB ********* //
    // BTCB -> ETH
    path = _encodePath(btcb, 2500, eth);
    _addPath(path);
    // BTCB -> WBNB
    path = _encodePath(btcb, 500, usdt, 100, wbnb);
    _addPath(path);
    // BTCB -> BUSD
    path = _encodePath(btcb, 500, busd);
    _addPath(path);
    // BTCB -> USDT
    path = _encodePath(btcb, 500, usdt);
    _addPath(path);
    // BTCB -> USDC
    path = _encodePath(btcb, 500, busd, 100, usdc);
    _addPath(path);
    // BTCB -> CAKE
    path = _encodePath(btcb, 500, usdt, 2500, cake);
    _addPath(path);
    // BTCB -> XRP
    path = _encodePath(btcb, 500, usdt, 500, wbnb, 2500, xrp);
    _addPath(path);

    // ********* ETH ********* //
    // ETH -> BTCB
    path = _encodePath(eth, 2500, btcb);
    _addPath(path);
    // ETH -> WBNB
    path = _encodePath(eth, 2500, wbnb);
    _addPath(path);
    // ETH -> BUSD
    path = _encodePath(eth, 500, usdc, 100, busd);
    _addPath(path);
    // ETH -> USDT
    path = _encodePath(eth, 500, usdc, 100, usdt);
    _addPath(path);
    // ETH -> USDC
    path = _encodePath(eth, 500, usdc);
    _addPath(path);
    // ETH -> CAKE
    path = _encodePath(eth, 500, usdc, 100, usdt, 2500, cake);
    _addPath(path);
    // ETH -> XRP
    path = _encodePath(eth, 2500, wbnb, 2500, xrp);
    _addPath(path);

    // ********* CAKE ********* //
    // CAKE -> BTCB
    path = _encodePath(cake, 2500, usdt, 500, btcb);
    _addPath(path);
    // CAKE -> WBNB
    path = _encodePath(cake, 2500, wbnb);
    _addPath(path);
    // CAKE -> BUSD
    path = _encodePath(cake, 2500, busd);
    _addPath(path);
    // CAKE -> USDT
    path = _encodePath(cake, 2500, usdt);
    _addPath(path);
    // CAKE -> USDC
    path = _encodePath(cake, 2500, usdt, 100, usdc);
    _addPath(path);
    // CAKE -> ETH
    path = _encodePath(cake, 2500, usdt, 100, usdc, 500, eth);
    _addPath(path);
    // CAKE -> XRP
    path = _encodePath(cake, 2500, wbnb, 2500, xrp);
    _addPath(path);

    // ********* XRP ********* //
    // XRP -> BTCB
    path = _encodePath(xrp, 2500, wbnb, 500, usdt, 500, btcb);
    _addPath(path);
    // XRP -> WBNB
    path = _encodePath(xrp, 2500, wbnb);
    _addPath(path);
    // XRP -> BUSD
    path = _encodePath(xrp, 2500, wbnb, 500, busd);
    _addPath(path);
    // XRP -> USDT
    path = _encodePath(xrp, 2500, wbnb, 100, usdt);
    _addPath(path);
    // XRP -> USDC
    path = _encodePath(xrp, 2500, wbnb, 500, usdt, 100, usdc);
    _addPath(path);
    // XRP -> ETH
    path = _encodePath(xrp, 2500, wbnb, 2500, eth);
    _addPath(path);
    // XRP -> CAKE
    path = _encodePath(xrp, 2500, wbnb, 2500, cake);
    _addPath(path);

    //---- execution ----//
    _startDeployerBroadcast();

    IUniSwapV3PathReader(pcsV3PathReader).setPaths(paths);

    _stopBroadcast();
  }

  function _encodePath(
    address _tokenA,
    uint24 _fee,
    address _tokenB
  ) internal pure returns (bytes memory pool) {
    pool = abi.encodePacked(_tokenA, _fee, _tokenB);
  }

  function _encodePath(
    address _tokenA,
    uint24 _fee0,
    address _tokenB,
    uint24 _fee1,
    address _tokenC
  ) internal pure returns (bytes memory pool) {
    pool = abi.encodePacked(_tokenA, _fee0, _tokenB, _fee1, _tokenC);
  }

  function _encodePath(
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

  function _addPath(bytes memory _path) internal {
    paths.push(_path);

    delete _path;
  }
}
