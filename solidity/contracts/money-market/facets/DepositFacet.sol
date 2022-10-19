// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IDepositFacet } from "../interfaces/IDepositFacet.sol";

contract DepositFacet is IDepositFacet {
  using SafeERC20 for ERC20;

  function deposit(address _token, uint256 _amount) external {
    ERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
  }
}
