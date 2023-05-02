// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface IAlpacaFlashloan {
  function AlpacaFlashloanCallback(address _token, uint256 _amount) external;
}
