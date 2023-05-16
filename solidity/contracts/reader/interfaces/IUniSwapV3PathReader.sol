// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface IUniSwapV3PathReader {
  function paths(address _source, address _destination) external returns (bytes memory);

  function setPaths(bytes[] calldata _paths) external;
}
