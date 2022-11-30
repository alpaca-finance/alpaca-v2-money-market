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
  event LogLiquidate(
    address indexed caller,
    address indexed liquidator,
    address _repayToken,
    address _collatToken,
    uint256 _repayAmount,
    uint256 _collatAmountOut
  );
  event LogLiquidateIb(
    address indexed caller,
    address indexed liquidator,
    address _repayToken,
    address _collatToken,
    uint256 _repayAmount,
    uint256 _ibCollatAmountOut,
    uint256 _underlyingAmountOut
  );

  error LiquidationFacet_Unauthorized();
  error LiquidationFacet_Healthy();
  error LiquidationFacet_RepayDebtValueTooHigh();
  error LiquidationFacet_InsufficientAmount();
  error LiquidationFacet_RepayAmountMismatch();

  function repurchase(
    address _account,
    uint256 _subAccountId,
    address _repayToken,
    address _collatToken,
    uint256 _amount
  ) external returns (uint256);

  function liquidationCall(
    address _liquidationStrat,
    address _account,
    uint256 _subAccountId,
    address _repayToken,
    address _collatToken,
    uint256 _repayAmount
  ) external;
}
