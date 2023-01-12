// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MockERC20 } from "./MockERC20.sol";

contract MockFeeOnTransferToken is MockERC20 {
  uint256 internal transferFeeBps;

  constructor(
    string memory name,
    string memory symbol,
    uint8 __decimals,
    uint256 _transferFeeBps
  ) MockERC20(name, symbol, __decimals) {
    transferFeeBps = _transferFeeBps;
  }

  function transfer(address to, uint256 amount) public virtual override returns (bool) {
    return super.transfer(to, (amount * (10000 - transferFeeBps)) / 10000);
  }

  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) public virtual override returns (bool) {
    return super.transferFrom(from, to, (amount * (10000 - transferFeeBps)) / 10000);
  }
}
