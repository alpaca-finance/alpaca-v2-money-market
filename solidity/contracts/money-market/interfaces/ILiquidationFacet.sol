// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface ILiquidationFacet {
  event LogRepurchase(
    address indexed repurchaser,
    address _repayToken,
    address _collatToken,
    uint256 _actualRepayAmountWithoutFee,
    uint256 _collatAmountOut,
    uint256 _feeToTreasury,
    uint256 _repurchaseRewardToCaller
  );
  event LogLiquidate(
    address indexed caller,
    address indexed liquidationStrategy,
    address _repayToken,
    address _collatToken,
    uint256 _amountDebtRepaid,
    uint256 _amountCollatLiquidated,
    uint256 _feeToTreasury
  );

  error LiquidationFacet_Unauthorized();
  error LiquidationFacet_Healthy();
  error LiquidationFacet_RepayAmountExceedThreshold();
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
    uint256 _repayAmount,
    bytes calldata _paramsForStrategy
  ) external;
}
