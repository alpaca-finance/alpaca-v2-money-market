// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface ILYFLiquidationFacet {
  event LogRepurchase(
    address indexed repurchaser,
    address _repayToken,
    address _collatToken,
    uint256 _amountIn,
    uint256 _amountOut
  );

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

  function liquidateLP(
    address _account,
    uint256 _subAccountId,
    address _lpToken,
    uint256 _lpAmountToLiquidate,
    uint256 _amount0ToRepay,
    uint256 _amount1ToRepay
  ) external;
}
