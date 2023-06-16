// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ILiquidationStrategy } from "../../contracts/money-market/interfaces/ILiquidationStrategy.sol";

contract MockBadLiquidationStrategy is ILiquidationStrategy {
  using SafeERC20 for ERC20;

  uint256 public amountToReturn;

  /// @dev swap collat for exact repay amount and send remaining collat to caller
  function executeLiquidation(
    address /* _collatToken */,
    address _repayToken,
    uint256 /*_collatAmount*/,
    uint256 /*_repayAmount*/,
    uint256 /*_minReceive*/,
    bytes memory /* _data */
  ) external {
    ERC20(_repayToken).safeTransfer(msg.sender, amountToReturn);
  }

  function setReturnRepayAmount(uint256 _amount) external {
    amountToReturn = _amount;
  }

  function setCallersOk(address[] calldata _callers, bool _isOk) external {}
}
