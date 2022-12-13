// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IAVFarmFacet {
  function deposit(
    address _token,
    uint256 _amountIn,
    uint256 _minReceive
  ) external;
}
