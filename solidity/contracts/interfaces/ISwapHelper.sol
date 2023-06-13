// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface ISwapHelper {
  struct SwapInfo {
    bytes swapCalldata;
    address router;
    uint256 amountInOffset;
    uint256 toOffset;
  }

  function getSwapCalldata(
    address _source,
    address _destination,
    uint256 _amountIn,
    address _to
  ) external view returns (bytes memory);

  function setSwapInfo(
    address _source,
    address _destination,
    SwapInfo calldata _swapInfo
  ) external;
}
