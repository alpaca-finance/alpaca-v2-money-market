// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface ILiquidationFacet {
  error LiquidationFacet_Unauthorized();
  error LiquidationFacet_Healthy();
  error LiquidationFacet_RepayAmountExceedThreshold();
  error LiquidationFacet_InsufficientAmount();
  error LiquidationFacet_RepayAmountMismatch();
  error LiquidationFacet_OnlyEOA();

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
    uint256 _repayAmount,
    uint256 _minReceive
  ) external;
}
