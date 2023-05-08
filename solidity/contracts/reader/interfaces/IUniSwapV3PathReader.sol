// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface IUniSwapV3PathReader {
  // Errors
  error PCSV3PathReader_NoLiquidity(address tokenA, address tokenB, uint24 fee);

  function setPaths(bytes[] calldata _paths) external;

  function paths(address _source, address _destination) external returns (bytes memory);
}
