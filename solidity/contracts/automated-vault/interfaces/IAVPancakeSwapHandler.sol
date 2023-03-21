// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// interfaces
import { ISwapPairLike } from "./ISwapPairLike.sol";
import { IAVHandler } from "./IAVHandler.sol";

interface IAVPancakeSwapHandler is IAVHandler {
  event LogOnWithdraw(address indexed _lpToken, uint256 _removedAmount);

  error AVPancakeSwapHandler_TooLittleReceived();
  error AVPancakeSwapHandler_TransferFailed();
  error AVPancakeSwapHandler_Reverse();
  error AVPancakeSwapHandler_Unauthorized(address);
}
