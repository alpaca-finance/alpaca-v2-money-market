// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IMoneyMarket {
  function nonCollatBorrow(address _token, uint256 _amount) external;
}
