// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { IUniSwapV2PathReader } from "solidity/contracts/reader/interfaces/IUniSwapV2PathReader.sol";

contract SetV2PathsScript is BaseScript {
  using stdJson for string;

  IUniSwapV2PathReader.PathParams[] paths;

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

    /* Template:
    {
      address _router = pancakeswapRouterV2;
      address[] memory _path = new address[](2);
      _path[0] = wbnb;
      _path[1] = busd;

      _setPath(_path);
    }
     */

    {
      address _router = pancakeswapRouterV2;
      address[] memory _path = new address[](2);
      _path[0] = wbnb;
      _path[1] = busd;

      _setPath(_router, _path);
    }

    _startDeployerBroadcast();

    IUniSwapV2PathReader(uniswapV2LikePathReader).setPaths(paths);

    _stopBroadcast();
  }

  function _setPath(address _router, address[] memory _path) internal {
    IUniSwapV2PathReader.PathParams memory _pathParam = IUniSwapV2PathReader.PathParams(_router, _path);
    paths.push(_pathParam);

    delete _pathParam;
  }
}
