// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface ISwapHelper {
  error SwapHelper_InvalidAgrument();

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
  ) external view returns (address, bytes memory);

  function setSwapInfo(
    address _source,
    address _destination,
    SwapInfo calldata _swapInfo
  ) external;

  function search(bytes memory _calldata, address _query) external pure returns (uint256 _offset);

  function search(bytes memory _calldata, uint256 _query) external pure returns (uint256 _offset);
}
