// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { SwapHelper } from "solidity/contracts/swap-helper/SwapHelper.sol";

import { ISwapHelper } from "solidity/contracts/interfaces/ISwapHelper.sol";
import { IPancakeSwapRouterV3 } from "solidity/contracts/money-market/interfaces/IPancakeSwapRouterV3.sol";

contract SetSwapInfoPancakeSwapV3Script is BaseScript {
  using stdJson for string;

  // pancake swap v3 offset configs (included 4 bytes of funcSig.)
  uint256 internal constant AMOUNT_IN_OFFSET = 132;
  uint256 internal constant TO_OFFSET = 68;
  uint256 internal constant MIN_AMOUNT_OUT_OFFSET = 164;

  ISwapHelper.PathInput[] internal pathInputs;

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

    // ********* WBNB ********* //
    // WBNB -> USDC:
    _encodeAndPushPath(wbnb, 500, usdt, 100, usdc);

    // WBNB -> USDT:
    _encodeAndPushPath(wbnb, 500, usdt);

    // WBNB -> BUSD:
    _encodeAndPushPath(wbnb, 500, busd);

    // WBNB -> BTCB:
    _encodeAndPushPath(wbnb, 100, usdt, 500, btcb);

    // WBNB -> ETH:
    _encodeAndPushPath(wbnb, 2500, eth);

    // WBNB -> CAKE:
    _encodeAndPushPath(wbnb, 2500, cake);

    // WBNB -> XRP:
    _encodeAndPushPath(wbnb, 2500, xrp);

    // ********* USDC ********* //
    // USDC -> BTCB:
    _encodeAndPushPath(usdc, 100, usdt, 500, btcb);

    // USDC -> ETH:
    _encodeAndPushPath(usdc, 500, eth);

    // USDC -> WBNB:
    _encodeAndPushPath(usdc, 100, usdt, 500, wbnb);

    // USDC -> BUSD:
    _encodeAndPushPath(usdc, 100, busd);

    // USDC -> USDT:
    _encodeAndPushPath(usdc, 100, usdt);

    // USDC -> CAKE:
    _encodeAndPushPath(usdc, 100, usdt, 2500, cake);

    // USDC -> XRP:
    _encodeAndPushPath(usdc, 100, usdt, 500, wbnb, 2500, xrp);

    // ********* USDT ********* //
    // USDT -> BTCB:
    _encodeAndPushPath(usdt, 500, btcb);

    // USDT -> ETH:
    _encodeAndPushPath(usdt, 100, usdc, 500, eth);

    // USDT -> WBNB:
    _encodeAndPushPath(usdt, 100, wbnb);

    // USDT -> BUSD:
    _encodeAndPushPath(usdt, 100, busd);

    // USDT -> USDC:
    _encodeAndPushPath(usdt, 100, usdc);

    // USDT -> CAKE:
    _encodeAndPushPath(usdt, 2500, cake);

    // USDT -> XRP:
    _encodeAndPushPath(usdt, 100, wbnb, 2500, xrp);

    // ********* BUSD ********* //
    // BUSD -> BTCB:
    _encodeAndPushPath(busd, 500, btcb);

    // BUSD -> ETH:
    _encodeAndPushPath(busd, 100, usdc, 500, eth);

    // BUSD -> WBNB:
    _encodeAndPushPath(busd, 100, usdt, 100, wbnb);

    // BUSD -> USDT:
    _encodeAndPushPath(busd, 100, usdt);

    // BUSD -> USDC:
    _encodeAndPushPath(busd, 100, usdc);

    // BUSD -> CAKE:
    _encodeAndPushPath(busd, 2500, cake);

    // BUSD -> XRP:
    _encodeAndPushPath(busd, 500, wbnb, 2500, xrp);

    // ********* BTCB ********* //
    // BTCB -> ETH
    _encodeAndPushPath(btcb, 2500, eth);

    // BTCB -> WBNB
    _encodeAndPushPath(btcb, 500, usdt, 100, wbnb);

    // BTCB -> BUSD
    _encodeAndPushPath(btcb, 500, busd);

    // BTCB -> USDT
    _encodeAndPushPath(btcb, 500, usdt);

    // BTCB -> USDC
    _encodeAndPushPath(btcb, 500, busd, 100, usdc);

    // BTCB -> CAKE
    _encodeAndPushPath(btcb, 500, usdt, 2500, cake);

    // BTCB -> XRP
    _encodeAndPushPath(btcb, 500, usdt, 500, wbnb, 2500, xrp);

    // ********* ETH ********* //
    // ETH -> BTCB
    _encodeAndPushPath(eth, 2500, btcb);

    // ETH -> WBNB
    _encodeAndPushPath(eth, 2500, wbnb);

    // ETH -> BUSD
    _encodeAndPushPath(eth, 500, usdc, 100, busd);

    // ETH -> USDT
    _encodeAndPushPath(eth, 500, usdc, 100, usdt);

    // ETH -> USDC
    _encodeAndPushPath(eth, 500, usdc);

    // ETH -> CAKE
    _encodeAndPushPath(eth, 500, usdc, 100, usdt, 2500, cake);

    // ETH -> XRP
    _encodeAndPushPath(eth, 2500, wbnb, 2500, xrp);

    // ********* CAKE ********* //
    // CAKE -> BTCB
    _encodeAndPushPath(cake, 2500, usdt, 500, btcb);

    // CAKE -> WBNB
    _encodeAndPushPath(cake, 2500, wbnb);

    // CAKE -> BUSD
    _encodeAndPushPath(cake, 2500, busd);

    // CAKE -> USDT
    _encodeAndPushPath(cake, 2500, usdt);

    // CAKE -> USDC
    _encodeAndPushPath(cake, 2500, usdt, 100, usdc);

    // CAKE -> ETH
    _encodeAndPushPath(cake, 2500, usdt, 100, usdc, 500, eth);

    // CAKE -> XRP
    _encodeAndPushPath(cake, 2500, wbnb, 2500, xrp);

    // ********* XRP ********* //
    // XRP -> BTCB
    _encodeAndPushPath(xrp, 2500, wbnb, 500, usdt, 500, btcb);

    // XRP -> WBNB
    _encodeAndPushPath(xrp, 2500, wbnb);

    // XRP -> BUSD
    _encodeAndPushPath(xrp, 2500, wbnb, 500, busd);

    // XRP -> USDT
    _encodeAndPushPath(xrp, 2500, wbnb, 100, usdt);

    // XRP -> USDC
    _encodeAndPushPath(xrp, 2500, wbnb, 500, usdt, 100, usdc);

    // XRP -> ETH
    _encodeAndPushPath(xrp, 2500, wbnb, 2500, eth);

    // XRP -> CAKE
    _encodeAndPushPath(xrp, 2500, wbnb, 2500, cake);

    _startDeployerBroadcast();

    swapHelper.setSwapInfos(pathInputs);

    _stopBroadcast();
  }

  function _preparePCSV3SwapInfo(bytes memory _path) internal view returns (ISwapHelper.SwapInfo memory) {
    // recipient, amountIn and amountOutMinimum will be replaced when calling `getSwapCalldata`
    address _to = address(moneyMarket);
    uint256 _amountIn = type(uint256).max / 5; // 0x333...
    uint256 _minAmountOut = type(uint256).max / 3; // 0x555...

    IPancakeSwapRouterV3.ExactInputParams memory _params = IPancakeSwapRouterV3.ExactInputParams({
      path: _path,
      recipient: _to,
      deadline: type(uint256).max, // 0xfff...
      amountIn: _amountIn,
      amountOutMinimum: _minAmountOut
    });

    bytes memory _calldata = abi.encodeCall(IPancakeSwapRouterV3.exactInput, _params);

    // cross check offset
    uint256 _amountInOffset = swapHelper.search(_calldata, _amountIn);
    uint256 _toOffset = swapHelper.search(_calldata, _to);
    uint256 _minAmountOutOffset = swapHelper.search(_calldata, _minAmountOut);

    assert(AMOUNT_IN_OFFSET == _amountInOffset);
    assert(TO_OFFSET == _toOffset);
    assert(MIN_AMOUNT_OUT_OFFSET == _minAmountOutOffset);

    return
      ISwapHelper.SwapInfo({
        swapCalldata: _calldata,
        router: pancakeswapRouterV3,
        amountInOffset: _amountInOffset,
        toOffset: _toOffset,
        minAmountOutOffset: _minAmountOutOffset
      });
  }

  function _addPathInput(
    address _source,
    address _destination,
    bytes memory _path
  ) internal {
    ISwapHelper.SwapInfo memory _info = _preparePCSV3SwapInfo(_path);

    ISwapHelper.PathInput memory _newPathInput = ISwapHelper.PathInput({
      source: _source,
      destination: _destination,
      info: _info
    });
    pathInputs.push(_newPathInput);
  }

  // encode path and push to array

  function _encodeAndPushPath(
    address _tokenA,
    uint24 _fee,
    address _tokenB
  ) internal {
    bytes memory _path = abi.encodePacked(_tokenA, _fee, _tokenB);
    _addPathInput(_tokenA, _tokenB, _path);
  }

  function _encodeAndPushPath(
    address _tokenA,
    uint24 _fee0,
    address _tokenB,
    uint24 _fee1,
    address _tokenC
  ) internal {
    bytes memory _path = abi.encodePacked(_tokenA, _fee0, _tokenB, _fee1, _tokenC);
    _addPathInput(_tokenA, _tokenC, _path);
  }

  function _encodeAndPushPath(
    address _tokenA,
    uint24 _fee0,
    address _tokenB,
    uint24 _fee1,
    address _tokenC,
    uint24 _fee2,
    address _tokenD
  ) internal {
    bytes memory _path = abi.encodePacked(_tokenA, _fee0, _tokenB, _fee1, _tokenC, _fee2, _tokenD);
    _addPathInput(_tokenA, _tokenD, _path);
  }
}
