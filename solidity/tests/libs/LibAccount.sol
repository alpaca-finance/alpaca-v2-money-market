// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "../interfaces/IERC20.sol";

library LibAccount {
  function myBalanceOf(address _account, address _token) internal view returns (uint256 _balance) {
    _balance = IERC20(_token).balanceOf(_account);
  }
}
