// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface ILiquidationStrategy {
  function executeLiquidation(
    address _collatToken,
    address _repayToken,
    uint256 _collatAmount,
    uint256 _repayAmount,
    bytes calldata _data
  ) external;

  function setCallersOk(address[] calldata _callers, bool _isOk) external;
}
