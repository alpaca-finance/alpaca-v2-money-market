// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface ILiquidationStrategy {
  function executeLiquidation(
    address _collatToken,
    address _repayToken,
    uint256 _repayAmount,
    address _repayTo,
    bytes calldata _data
  ) external;
}
