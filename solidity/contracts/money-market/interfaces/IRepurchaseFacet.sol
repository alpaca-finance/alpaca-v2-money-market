// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IRepurchaseFacet {
  event LogRepurchase(
    address indexed repurchaser,
    address _repayToken,
    address _collatToken,
    uint256 _amountIn,
    uint256 _amountOut
  );

  error RepurchaseFacet_Healthy();
  error RepurchaseFacet_RepayDebtValueTooHigh();
  error RepurchaseFacet_InsufficientAmount();

  function repurchase(
    address _account,
    uint256 _subAccountId,
    address _repayToken,
    address _collatToken,
    uint256 _amount
  ) external returns (uint256);
}
