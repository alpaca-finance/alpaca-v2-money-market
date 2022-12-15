// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IAVTradeFacet {
  event LogRemoveDebt(address indexed shareToken, uint256 debtShareRemoved, uint256 debtValueRemoved);
  event LogDeposit(
    address indexed user,
    address indexed shareToken,
    address stableToken,
    uint256 amountStableDeposited
  );

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
}
