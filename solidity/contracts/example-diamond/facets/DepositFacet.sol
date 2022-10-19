// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract DepositFacet {
  using SafeERC20 for ERC20;

  function deposit(
    address _token,
    address _user,
    uint256 _amount
  ) external {
    // who is msg.sender in this content? => expected to be MoneyMarket
    ERC20(_token).safeTransferFrom(_user, msg.sender, _amount);
  }
}
