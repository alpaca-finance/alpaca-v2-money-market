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

    // All pair will be added both forward and reverse path

    // ********* 1 Hops *********

    /// BUSD

    _encodeAndPushPath(wbnb, 500, busd);

    _encodeAndPushPath(usdc, 100, busd);

    _encodeAndPushPath(usdt, 100, busd);

    _encodeAndPushPath(btcb, 500, busd);

    /// USDC

    _encodeAndPushPath(eth, 500, usdc);

    /// WBNB

    _encodeAndPushPath(cake, 500, wbnb);

    _encodeAndPushPath(xrp, 2500, wbnb);

    _encodeAndPushPath(doge, 2500, wbnb);

    _encodeAndPushPath(ltc, 2500, wbnb);

    _encodeAndPushPath(ada, 2500, wbnb);

    // ********* 2 Hops *********

    _encodeAndPushPath(eth, 500, usdc, 100, busd);

    _encodeAndPushPath(cake, 500, wbnb, 500, busd);

    _encodeAndPushPath(xrp, 2500, wbnb, 500, busd);

    _encodeAndPushPath(doge, 2500, wbnb, 500, busd);

    _encodeAndPushPath(ltc, 2500, wbnb, 500, busd);

    _encodeAndPushPath(ada, 2500, wbnb, 500, busd);

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
    bytes memory _reversePath = abi.encodePacked(_tokenB, _fee, _tokenA);

    _addPathInput(_tokenA, _tokenB, _path);
    _addPathInput(_tokenB, _tokenA, _reversePath);
  }

  function _encodeAndPushPath(
    address _tokenA,
    uint24 _fee0,
    address _tokenB,
    uint24 _fee1,
    address _tokenC
  ) internal {
    bytes memory _path = abi.encodePacked(_tokenA, _fee0, _tokenB, _fee1, _tokenC);
    bytes memory _reversePath = abi.encodePacked(_tokenC, _fee1, _tokenB, _fee0, _tokenA);

    _addPathInput(_tokenA, _tokenC, _path);
    _addPathInput(_tokenC, _tokenA, _reversePath);
  }
}
