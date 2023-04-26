// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface IPancakeSwapPathV3Reader {
  function setPaths(bytes[] calldata _paths) external;

  function paths(address _source, address _destination) external returns (bytes memory);
}
