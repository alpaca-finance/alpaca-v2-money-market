// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ILiquidationStrategy } from "../../contracts/money-market/interfaces/ILiquidationStrategy.sol";

contract MockBadLiquidationStrategy is ILiquidationStrategy {
  using SafeERC20 for ERC20;

  /// @dev swap collat for exact repay amount and send remaining collat to caller
  function executeLiquidation(
    address, /* _collatToken */
    address _repayToken,
    uint256, /*_collatAmount*/
    uint256 _repayAmount,
    bytes calldata /* _data */
  ) external {
    ERC20(_repayToken).safeTransfer(msg.sender, _repayAmount - 1);
  }

  function setCallersOk(address[] calldata _callers, bool _isOk) external {}
}
