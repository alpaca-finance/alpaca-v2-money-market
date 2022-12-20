// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface IAVTradeFacet {
  event LogRemoveDebt(address indexed shareToken, uint256 debtShareRemoved, uint256 debtValueRemoved);
  event LogDeposit(
    address indexed user,
    address indexed shareToken,
    address stableToken,
    uint256 amountStableDeposited
  );
  // todo: add fields
  event LogWithdraw(
    address indexed user,
    address indexed shareToken,
    uint256 burnedAmount,
    address stableToken,
    uint256 returnedAmount
  );

  error AVTradeFacet_TooLittleReceived();
  error AVTradeFacet_InsufficientAmount();

  function deposit(
    address _shareToken,
    uint256 _amountIn,
    uint256 _minShareOut
  ) external;

  function withdraw(
    address _shareToken,
    uint256 _shareAmountIn,
    uint256 _minTokenOut
  ) external;

  function getDebtValues(address _shareToken) external view returns (uint256, uint256);
}
