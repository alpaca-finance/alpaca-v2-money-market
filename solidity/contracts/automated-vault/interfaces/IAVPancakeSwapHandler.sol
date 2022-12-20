// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// interfaces
import { ISwapPairLike } from "./ISwapPairLike.sol";
import { IAVHandler } from "./IAVHandler.sol";

interface IAVPancakeSwapHandler is IAVHandler {
  error AVPancakeSwapHandler_TooLittleReceived();
  error AVPancakeSwapHandler_TransferFailed();
  error AVPancakeSwapHandler_Reverse();
  error AVPancakeSwapHandler_Unauthorized(address);
}
