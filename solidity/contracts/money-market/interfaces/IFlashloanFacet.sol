// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface IFlashloanFacet {
  // Errors
  error FlashloanFacet_InvalidToken(address _token);
  error FlashloanFacet_NotEnoughToken(uint256 _amount);
  error FlashloanFacet_NotEnoughRepay();

  /// @notice Receive token0 and/or token1 and pay it back, plus a fee, in the callback
  /// @dev The caller of this method receives a callback in the form of IAlpacaFlashloanCallback#alpacaFlashloanCallback
  /// @param _token The address of loan token
  /// @param _amount The amount of the loan token
  /// @param _data Any data to be passed through to the callback
  function flashloan(
    address _token,
    uint256 _amount,
    bytes calldata _data
  ) external;
}
