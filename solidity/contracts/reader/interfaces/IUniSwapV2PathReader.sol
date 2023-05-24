// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface IUniSwapV2PathReader {
  struct PathParams {
    address router;
    address[] path;
  }

  function getPath(address _source, address _destination) external view returns (PathParams memory);

  function setPaths(PathParams[] calldata _inputs) external;
}
