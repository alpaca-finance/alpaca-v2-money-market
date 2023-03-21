// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface IDebtToken {
  error DebtToken_UnApprovedHolder();
  error DebtToken_NoSelfTransfer();

  function initialize(address asset_, address moneyMarket_) external;

  function setOkHolders(address[] calldata _okHolders, bool _isOk) external;

  function mint(address to, uint256 amount) external;

  function burn(address from, uint256 amount) external;

  function decimals() external view returns (uint8);
}
