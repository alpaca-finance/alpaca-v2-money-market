// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface ILiquidator {
  function liquidate(
    address _collatToken,
    address _repayToken,
    uint256 _repayAmount
  ) external;
}
