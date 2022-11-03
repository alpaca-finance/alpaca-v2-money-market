// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IRepurchaseFacet {
  function repurchase(
    address _subAccount,
    address _debtToken,
    address _collatToken,
    uint256 _amount
  ) external returns (uint256);
}
