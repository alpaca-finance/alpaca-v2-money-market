// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { SwapHelper } from "solidity/contracts/swap-helper/SwapHelper.sol";

import { ISwapHelper } from "solidity/contracts/interfaces/ISwapHelper.sol";
import { IThenaRouterV3 } from "solidity/contracts/interfaces/IThenaRouterV3.sol";

contract SetSwapInfoThenaFusion is BaseScript {
  using stdJson for string;

  // thena dex fusion offset configs (included 4 bytes of funcSig.)
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

    // Thena Fusion use SwapRouter (RouterV3)

    // WBNB -> THE (Liquidation)
    _addPathInput(wbnb, the);

    _startDeployerBroadcast();

    swapHelper.setSwapInfos(pathInputs);

    _stopBroadcast();
  }

  function _prepareThenaFusionSwapInfo(address _source, address _destination)
    internal
    view
    returns (ISwapHelper.SwapInfo memory)
  {
    // recipient, amountIn and amountOutMinimum will be replaced when calling `getSwapCalldata`
    address _to = address(moneyMarket);
    uint256 _amountIn = type(uint256).max / 5; // 0x333...
    uint256 _minAmountOut = type(uint256).max / 3; // 0x555...

    IThenaRouterV3.ExactInputSingleParams memory _params = IThenaRouterV3.ExactInputSingleParams({
      tokenIn: _source,
      tokenOut: _destination,
      recipient: _to,
      deadline: type(uint256).max,
      amountIn: _amountIn,
      amountOutMinimum: _minAmountOut,
      limitSqrtPrice: 0
    });

    bytes memory _calldata = abi.encodeCall(IThenaRouterV3.exactInputSingle, (_params));

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
        router: thenaSwapRouterV3,
        amountInOffset: _amountInOffset,
        toOffset: _toOffset,
        minAmountOutOffset: _minAmountOutOffset
      });
  }

  function _addPathInput(address _source, address _destination) internal {
    ISwapHelper.SwapInfo memory _info = _prepareThenaFusionSwapInfo(_source, _destination);

    ISwapHelper.PathInput memory _newPathInput = ISwapHelper.PathInput({
      source: _source,
      destination: _destination,
      info: _info
    });
    pathInputs.push(_newPathInput);
  }
}
