// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// interfaces
import { IFeeModel } from "../interfaces/IFeeModel.sol";

contract FixedFeeModel500Bps is IFeeModel {
  /// @notice Get a static fee
  function getFeeBps(
    uint256, /*_total*/
    uint256 /*_used*/
  ) external pure returns (uint256 _interestRate) {
    return 500;
  }
}
