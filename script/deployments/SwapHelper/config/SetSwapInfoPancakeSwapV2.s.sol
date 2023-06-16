// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { SwapHelper } from "solidity/contracts/swap-helper/SwapHelper.sol";

import { ISwapHelper } from "solidity/contracts/interfaces/ISwapHelper.sol";
import { IPancakeRouter02 } from "solidity/contracts/money-market/interfaces/IPancakeRouter02.sol";

contract SetSwapInfoPancakeSwapV2Script is BaseScript {
  using stdJson for string;

  // pancake swap v2 offset configs (included 4 bytes of funcSig.)
  uint256 internal constant AMOUNT_IN_OFFSET = 4;
  uint256 internal constant TO_OFFSET = 100;
  uint256 internal constant MIN_AMOUNT_OUT_OFFSET = 36;

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
    // WBNB -> HIGH:
    _encodeAndPushPath(wbnb, busd, high);

    // ********* USDC ********* //
    // USDC -> HIGH:
    _encodeAndPushPath(usdc, busd, high);

    // ********* USDT ********* //
    // USDT -> HIGH:
    _encodeAndPushPath(usdt, busd, high);

    // ********* BUSD ********* //
    // BUSD -> HIGH:
    _encodeAndPushPath(busd, high);

    // ********* BTCB ********* //
    // BTCB -> HIGH:
    _encodeAndPushPath(btcb, busd, high);

    // ********* ETH ********* //
    // ETH -> HIGH:
    _encodeAndPushPath(eth, busd, high);

    // ********* CAKE ********* //
    // CAKE -> HIGH:
    _encodeAndPushPath(cake, busd, high);

    // ********* XRP ********* //
    // XRP -> HIGH:
    _encodeAndPushPath(xrp, busd, high);

    // ********* HIGH ********* //
    // HIGH -> BUSD:
    _encodeAndPushPath(high, busd);

    _startDeployerBroadcast();

    swapHelper.setSwapInfos(pathInputs);

    _stopBroadcast();
  }

  function _preparePCSV2SwapInfo(address[] memory _path) internal view returns (ISwapHelper.SwapInfo memory) {
    // recipient, amountIn and amountOutMinimum will be replaced when calling `getSwapCalldata`
    address _to = address(moneyMarket);
    uint256 _amountIn = type(uint256).max / 5; // 0x333...
    uint256 _minAmountOut = type(uint256).max / 3; // 0x555...

    bytes memory _calldata = abi.encodeCall(
      IPancakeRouter02.swapExactTokensForTokens,
      (_amountIn, _minAmountOut, _path, _to, type(uint256).max)
    );

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
        router: pancakeswapRouterV2,
        amountInOffset: _amountInOffset,
        toOffset: _toOffset,
        minAmountOutOffset: _minAmountOutOffset
      });
  }

  function _addPathInput(
    address _source,
    address _destination,
    address[] memory _path
  ) internal {
    ISwapHelper.SwapInfo memory _info = _preparePCSV2SwapInfo(_path);

    ISwapHelper.PathInput memory _newPathInput = ISwapHelper.PathInput({
      source: _source,
      destination: _destination,
      info: _info
    });
    pathInputs.push(_newPathInput);
  }

  // encode path and push to array

  function _encodeAndPushPath(address _token0, address _token1) internal {
    address[] memory _path = new address[](2);
    _path[0] = _token0;
    _path[1] = _token1;
    _addPathInput(_token0, _token1, _path);
  }

  function _encodeAndPushPath(
    address _token0,
    address _token1,
    address _token2
  ) internal {
    address[] memory _path = new address[](3);
    _path[0] = _token0;
    _path[1] = _token1;
    _path[2] = _token2;
    _addPathInput(_token0, _token2, _path);
  }
}
