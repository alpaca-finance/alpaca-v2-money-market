// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface IAVTradeFacet {
  error AVTradeFacet_TooLittleReceived();

  function deposit(
    address _vaultToken,
    uint256 _stableAmountIn,
    uint256 _minShareOut
  ) external;

  function withdraw(
    address _vaultToken,
    uint256 _shareToWithdraw,
    uint256 _minStableTokenOut,
    uint256 _minAssetTokenOut
  ) external;
}
