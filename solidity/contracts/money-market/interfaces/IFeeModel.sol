// SPDX-License-Identifier: BUSL
pragma solidity >=0.8.19;

interface IFeeModel {
  function getFeeBps(uint256 _total, uint256 _used) external pure returns (uint256);
}
