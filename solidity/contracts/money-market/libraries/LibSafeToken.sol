// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

library LibSafeToken {
  function safeTransferETH(address to, uint256 value) internal {
    // solhint-disable-next-line no-call-value
    (bool success, ) = to.call{ value: value }(new bytes(0));
    require(success, "!safeTransferETH");
  }
}
