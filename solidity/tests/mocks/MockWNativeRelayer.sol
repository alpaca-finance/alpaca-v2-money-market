// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IWNative } from "../../contracts/money-market/interfaces/IWNative.sol";

contract MockWNativeRelayer {
  address private wnative;

  constructor(address _wnative) public {
    wnative = _wnative;
  }

  function withdraw(uint256 _amount) external {
    IWNative(wnative).withdraw(_amount);
    (bool success, ) = msg.sender.call{ value: _amount }("");
    require(success, "WNativeRelayer::onlyWhitelistedCaller:: can't withdraw");
  }

  receive() external payable {}
}
