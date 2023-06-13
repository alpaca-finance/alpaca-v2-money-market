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

    // TODO: calculate offset for amountIn and to before setSwapInfo

    address _source = address(0x0);
    address _destination = address(0x0);
    address _router = address(0x0);

    ISwapHelper.SwapInfo memory _swapInfo = ISwapHelper.SwapInfo({
      swapCalldata: "",
      router: _router,
      amountInOffset: 0,
      toOffset: 0
    });

    _startDeployerBroadcast();

    swapHelper.setSwapInfo(_source, _destination, _swapInfo);

    _stopBroadcast();
  }
}
