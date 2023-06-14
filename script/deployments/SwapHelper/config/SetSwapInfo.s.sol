// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { SwapHelper } from "solidity/contracts/swap-helper/SwapHelper.sol";

import { ISwapHelper } from "solidity/contracts/interfaces/ISwapHelper.sol";

contract SetSwapInfoScript is BaseScript {
  using stdJson for string;

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
    // TODO: create `SetSwapInfo` script for specific DEX (e.g. SetSwapInfoPancakeSwapV3)
    uint256 _amountIn = 1;
    uint256 _minAmountOut = 1; // _minAmountOut should be greater than 0 when setSwapInfo
    address _to = address(0x0);

    address _source = address(0x0);
    address _destination = address(0x0);
    address _router = address(0x0);

    bytes memory _calldata = abi.encodeWithSignature("mockCall(address)", address(0x0));

    ISwapHelper.SwapInfo memory _swapInfo = ISwapHelper.SwapInfo({
      swapCalldata: _calldata,
      router: _router,
      amountInOffset: swapHelper.search(_calldata, _amountIn),
      toOffset: swapHelper.search(_calldata, _to),
      minAmountOutOffset: swapHelper.search(_calldata, _minAmountOut)
    });

    _startDeployerBroadcast();

    swapHelper.setSwapInfo(_source, _destination, _swapInfo);

    _stopBroadcast();
  }
}
