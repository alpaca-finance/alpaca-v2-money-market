// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface IAlpacaFlashloanCallback {
  /// @notice Called to `msg.sender` after executing a flashloan via IFlashloanFacet#flashloan.
  /// @param _token The address of loan token
  /// @param _repay The atleast amount that msg.sender required for pay back
  /// @param _data Any data to be passed through to the callback
  function alpacaFlashloanCallback(
    address _token,
    uint256 _repay,
    bytes calldata _data
  ) external;
}
