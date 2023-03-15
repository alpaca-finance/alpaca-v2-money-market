// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface IAVHandler {
  function totalLpBalance() external view returns (uint256);

  function onDeposit(
    address _stableToken,
    address _assetToken,
    uint256 _stableAmount,
    uint256 _assetAmount,
    uint256 _minLpAmount
  ) external returns (uint256);

  function onWithdraw(uint256 _valueToRemove) external returns (uint256, uint256);

  function setWhitelistedCallers(address[] calldata _callers, bool _isOk) external;

  function calculateBorrowAmount(uint256 _stableDepositedAmount)
    external
    view
    returns (uint256 _stableBorrowAmount, uint256 _assetBorrowAmount);

  function getAUMinUSD() external view returns (uint256);
}
