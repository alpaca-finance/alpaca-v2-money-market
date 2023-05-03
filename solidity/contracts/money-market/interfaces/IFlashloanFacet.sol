// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface IFlashloanFacet {
  ///@dev  The caller of this method receives a callback in the form of IAlpacaFlashloanCallback#alpacaFlashloanCallback
  //@param the confirm yet
  function flashloan(
    address _token,
    uint256 _amount,
    bytes calldata _data
  ) external;
}
