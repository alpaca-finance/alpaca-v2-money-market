// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import { IUniSwapV2PathReader } from "./interfaces/IUniSwapV2PathReader.sol";
import { IPancakeRouter02 } from "../money-market/interfaces/IPancakeRouter02.sol";

// return router, return path
contract PCSV2PathReader is IUniSwapV2PathReader {
  event LogSetPath(address _source, address _destination, address[] _path);

  mapping(address => mapping(address => PathParams)) internal paths;

  constructor() {}

  function getPath(address _source, address _destination) external view returns (PathParams memory) {
    return paths[_source][_destination];
  }

  function setPaths(PathParams[] calldata _inputs) external {
    uint256 _len = _inputs.length;
    PathParams memory _params;
    for (uint256 _i; _i < _len; ) {
      _params = _inputs[_i];
      address[] memory _path = _params.path;
      address _router = _params.router;

      // sanity check. router will revert if pair doesn't exist
      IPancakeRouter02(_router).getAmountsIn(1 ether, _path);

      paths[_path[0]][_path[_path.length - 1]] = _params;

      unchecked {
        ++_i;
      }
      emit LogSetPath(_path[0], _path[_path.length - 1], _path);
    }
  }
}
