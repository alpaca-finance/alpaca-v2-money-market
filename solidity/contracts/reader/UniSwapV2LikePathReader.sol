// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IUniSwapV2PathReader } from "./interfaces/IUniSwapV2PathReader.sol";
import { IPancakeRouter02 } from "../money-market/interfaces/IPancakeRouter02.sol";

/// @title UniSwapV2LikePathReader - Return router and part to swap on UniSwapV2-fork DEX
contract UniSwapV2LikePathReader is IUniSwapV2PathReader, Ownable {
  event LogSetPath(address _source, address _destination, address[] _path);

  // sourceToken => destinationToken => pathParams
  mapping(address => mapping(address => PathParams)) internal paths;

  /// @notice Get a path from given source and destination tokens
  /// @dev Function will return router and path
  /// @param _source The source token address
  /// @param _destination The destination token address
  /// @return PathParams The path parameters (containing router and path)
  function getPath(address _source, address _destination) external view returns (PathParams memory) {
    return paths[_source][_destination];
  }

  /// @notice Sets path configurations v2
  /// @param _inputs An array of PathParams (each PathParams must contain router and path)
  function setPaths(PathParams[] calldata _inputs) external onlyOwner {
    uint256 _len = _inputs.length;
    PathParams memory _params;
    for (uint256 _i; _i < _len; ) {
      _params = _inputs[_i];
      address[] memory _path = _params.path;
      address _router = _params.router;

      // sanity check. router will revert if pair doesn't exist
      IPancakeRouter02(_router).getAmountsIn(1 ether, _path);

      paths[_path[0]][_path[_path.length - 1]] = _params;

      emit LogSetPath(_path[0], _path[_path.length - 1], _path);
      unchecked {
        ++_i;
      }
    }
  }
}
