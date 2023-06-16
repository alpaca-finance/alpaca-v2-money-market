// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface ISwapHelper {
  error SwapHelper_InvalidAgrument();
  error SwapHelper_SwapInfoNotFound(address _source, address _destination);


  struct SwapInfo {
    bytes swapCalldata;
    address router;
    uint256 amountInOffset;
    uint256 toOffset;
    uint256 minAmountOutOffset;
  }

  struct PathInput {
    address source;
    address destination;
    SwapInfo info;
  }

  function getSwapCalldata(
    address _source,
    address _destination,
    uint256 _amountIn,
    address _to,
    uint256 _minAmountOut
  ) external view returns (address, bytes memory);

  function setSwapInfos(PathInput[] calldata _pathInputs) external;

  function search(bytes memory _calldata, address _query) external pure returns (uint256 _offset);

  function search(bytes memory _calldata, uint256 _query) external pure returns (uint256 _offset);
}
