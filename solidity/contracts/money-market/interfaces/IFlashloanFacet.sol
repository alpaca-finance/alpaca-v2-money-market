// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface IFlashloanFacet {
  function flashloan(address _token, uint256 _amount) external;
}
