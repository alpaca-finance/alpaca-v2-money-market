// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface ILiquidationFacet {
  event LogRepurchase(
    address indexed repurchaser,
    address _repayToken,
    address _collatToken,
    uint256 _amountIn,
    uint256 _amountOut
  );

  error LiquidationFacet_Unauthorized();
  error LiquidationFacet_Healthy();
  error LiquidationFacet_RepayDebtValueTooHigh();
  error LiquidationFacet_InsufficientAmount();

  function repurchase(
    address _account,
    uint256 _subAccountId,
    address _repayToken,
    address _collatToken,
    uint256 _amount
  ) external returns (uint256);
}
