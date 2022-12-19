// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// interfaces
import { ISwapPairLike } from "../interfaces/ISwapPairLike.sol";

interface IAVPancakeSwapHandler {
  error AVPancakeSwapHandler_TooLittleReceived();
  error AVPancakeSwapHandler_TransferFailed();
  error AVPancakeSwapHandler_Reverse();

  function totalLpBalance() external view returns (uint256);

  function onDeposit(
    address _token0,
    address _token1,
    uint256 _token0Amount,
    uint256 _token1Amount,
    uint256 _minLPAmount
  ) external returns (uint256);

  function onWithdraw(uint256 _lpToRemove) external returns (uint256, uint256);
}
