// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// interfaces
import { IAVHandler } from "../interfaces/IAVHandler.sol";

contract AVHandler is IAVHandler {
  using SafeERC20 for ERC20;

  function onDeposit(
    address _depositFrom,
    address _token,
    uint256 _amount
  ) external returns (uint256) {
    ERC20(_token).safeTransferFrom(_depositFrom, address(this), _amount);
    return ERC20(_token).balanceOf(address(this));
  }
}
