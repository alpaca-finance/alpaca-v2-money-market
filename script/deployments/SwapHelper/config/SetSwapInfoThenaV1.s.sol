// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { SwapHelper } from "solidity/contracts/swap-helper/SwapHelper.sol";

import { ISwapHelper } from "solidity/contracts/interfaces/ISwapHelper.sol";
import { IThenaRouterV2 } from "solidity/contracts/interfaces/IThenaRouterV2.sol";

contract SetSwapInfoThenaV1 is BaseScript {
  using stdJson for string;

  // thena dex v1 offset configs (included 4 bytes of funcSig.)
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

    // Thena V1 use RouterV2

    // THE -> BUSD (Treasury)
    _encodeAndPushPath(the, busd, false);
    // BUSD -> THE (Repurchase)
    _encodeAndPushPath(busd, the, false);

    _startDeployerBroadcast();

    swapHelper.setSwapInfos(pathInputs);

    _stopBroadcast();
  }

  function _prepareThenaV1SwapInfo(IThenaRouterV2.route[] memory _routes)
    internal
    view
    returns (ISwapHelper.SwapInfo memory)
  {
    // recipient, amountIn and amountOutMinimum will be replaced when calling `getSwapCalldata`
    address _to = address(moneyMarket);
    uint256 _amountIn = type(uint256).max / 5; // 0x333...
    uint256 _minAmountOut = type(uint256).max / 3; // 0x555...

    bytes memory _calldata = abi.encodeCall(
      IThenaRouterV2.swapExactTokensForTokens,
      (_amountIn, _minAmountOut, _routes, _to, type(uint256).max)
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
        router: thenaSwapRouterV2,
        amountInOffset: _amountInOffset,
        toOffset: _toOffset,
        minAmountOutOffset: _minAmountOutOffset
      });
  }

  function _addPathInput(
    address _source,
    address _destination,
    IThenaRouterV2.route[] memory _routes
  ) internal {
    ISwapHelper.SwapInfo memory _info = _prepareThenaV1SwapInfo(_routes);

    ISwapHelper.PathInput memory _newPathInput = ISwapHelper.PathInput({
      source: _source,
      destination: _destination,
      info: _info
    });
    pathInputs.push(_newPathInput);
  }

  // encode path and push to array

  function _encodeAndPushPath(
    address _token0,
    address _token1,
    bool _stable
  ) internal {
    IThenaRouterV2.route[] memory _routes = new IThenaRouterV2.route[](1);
    _routes[0] = IThenaRouterV2.route({ from: _token0, to: _token1, stable: _stable });
    _addPathInput(_token0, _token1, _routes);
  }
}
