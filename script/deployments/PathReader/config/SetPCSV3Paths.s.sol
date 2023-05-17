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
    path = _encodePath(wbnb, 2500, btcb);
    _addPath(path);
    // WBNB -> ETH:
    path = _encodePath(wbnb, 2500, eth);
    _addPath(path);

    // ********* USDC ********* //
    // USDC -> BTCB:
    path = _encodePath(usdc, 100, busd, 500, btcb);
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

    // ********* USDT ********* //
    // USDT -> BTCB:
    path = _encodePath(usdt, 500, btcb);
    _addPath(path);
    // USDT -> ETH:
    path = _encodePath(usdt, 500, wbnb, 2500, eth);
    _addPath(path);
    // USDT -> WBNB:
    path = _encodePath(usdt, 500, wbnb);
    _addPath(path);
    // USDT -> BUSD:
    path = _encodePath(usdt, 100, busd);
    _addPath(path);
    // USDT -> USDC:
    path = _encodePath(usdt, 100, usdc);
    _addPath(path);

    // ********* BUSD ********* //
    // BUSD -> BTCB:
    path = _encodePath(busd, 500, btcb);
    _addPath(path);
    // BUSD -> ETH:
    path = _encodePath(busd, 500, wbnb, 2500, eth);
    _addPath(path);
    // BUSD -> WBNB:
    path = _encodePath(busd, 500, wbnb);
    _addPath(path);
    // BUSD -> USDT:
    path = _encodePath(busd, 100, usdt);
    _addPath(path);
    // BUSD -> USDC:
    path = _encodePath(busd, 100, usdc);
    _addPath(path);

    // ********* BTCB ********* //
    // BTCB -> ETH
    path = _encodePath(btcb, 2500, eth);
    _addPath(path);
    // BTCB -> WBNB
    path = _encodePath(btcb, 2500, wbnb);
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

    // ********* ETH ********* //
    // ETH -> BTCB
    path = _encodePath(eth, 2500, btcb);
    _addPath(path);
    // ETH -> WBNB
    path = _encodePath(eth, 2500, wbnb);
    _addPath(path);
    // ETH -> BUSD
    path = _encodePath(eth, 2500, wbnb, 500, busd);
    _addPath(path);
    // ETH -> USDT
    path = _encodePath(eth, 2500, wbnb, 500, usdt);
    _addPath(path);
    // ETH -> USDC
    path = _encodePath(eth, 500, usdc);
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

  function _addPath(bytes memory path) internal {
    paths.push(path);

    delete path;
  }
}
