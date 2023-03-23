// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface IWNativeRelayer {
  function withdraw(uint256 _amount) external;

  function setCallerOk(address[] calldata whitelistedCallers, bool isOk) external;
}
