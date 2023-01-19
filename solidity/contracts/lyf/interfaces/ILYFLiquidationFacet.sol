// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface ILYFLiquidationFacet {
  error LYFLiquidationFacet_Unauthorized();
  error LYFLiquidationFacet_Healthy();
  error LYFLiquidationFacet_RepayDebtValueTooHigh();
  error LYFLiquidationFacet_InsufficientAmount();
  error LYFLiquidationFacet_TooLittleReceived();
  error LYFLiquidationFacet_InvalidAssetTier();

  function repurchase(
    address _account,
    uint256 _subAccountId,
    address _repayToken,
    address _collatToken,
    address _lpToken,
    uint256 _amountDebtToRepurchase,
    uint256 _minCollatOut
  ) external returns (uint256);

  function lpLiquidationCall(
    address _account,
    uint256 _subAccountId,
    address _lpToken,
    uint256 _lpAmountToLiquidate,
    uint256 _amount0ToRepay,
    uint256 _amount1ToRepay
  ) external;

  function liquidationCall(
    address _liquidationStrat,
    address _account,
    uint256 _subAccountId,
    address _repayToken,
    address _lpToken,
    address _collatToken,
    uint256 _repayAmount,
    uint256 _minReceive
  ) external;
}
