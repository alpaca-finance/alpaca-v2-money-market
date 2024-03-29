// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IWNative } from "../../contracts/interfaces/IWNative.sol";

contract MockWNativeRelayer {
  address private wnative;

  constructor(address _wnative) {
    wnative = _wnative;
  }

  function withdraw(uint256 _amount) external {
    IWNative(wnative).withdraw(_amount);
    (bool success, ) = msg.sender.call{ value: _amount }("");
    require(success, "WNativeRelayer::onlyWhitelistedCaller:: can't withdraw");
  }

  receive() external payable {}
}
