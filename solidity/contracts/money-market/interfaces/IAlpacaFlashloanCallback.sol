// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface IAlpacaFlashloanCallback {
  // @notice Called to `msg.sender` after executing a flashloan via IFlashloanFacet#flashloan.
  // TODO: params not confirm yet
  function alpacaFlashloanCallback(
    address _token,
    uint256 _amount,
    uint256 _expectedFee
  ) external;
}
