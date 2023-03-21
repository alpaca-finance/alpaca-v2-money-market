// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MockERC20 } from "./MockERC20.sol";

contract MockFeeOnTransferToken is MockERC20 {
  uint256 public transferFeeBps;

  constructor(
    string memory name,
    string memory symbol,
    uint8 __decimals,
    uint256 _transferFeeBps
  ) MockERC20(name, symbol, __decimals) {
    transferFeeBps = _transferFeeBps;
  }

  function transfer(address to, uint256 amount) public virtual override returns (bool) {
    uint256 _fee = (amount * (transferFeeBps)) / 10000;
    _burn(msg.sender, _fee);
    return super.transfer(to, amount - _fee);
  }

  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) public virtual override returns (bool) {
    uint256 _fee = (amount * (transferFeeBps)) / 10000;
    _burn(from, _fee);
    return super.transferFrom(from, to, amount - _fee);
  }

  function setFee(uint256 _newFeeBps) external {
    transferFeeBps = _newFeeBps;
  }
}
