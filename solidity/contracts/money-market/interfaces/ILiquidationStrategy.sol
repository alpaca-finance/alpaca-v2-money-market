// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface ILiquidationStrategy {
  function executeLiquidation(
    address _collatToken,
    address _repayToken,
    uint256 _collatAmountIn,
    uint256 _repayAmount,
    uint256 _minReceive,
    bytes memory _data
  ) external;

  function setCallersOk(address[] calldata _callers, bool _isOk) external;
}
