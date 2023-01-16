// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface IAVTradeFacet {
  event LogRemoveDebt(address indexed vaultToken, uint256 debtShareRemoved, uint256 debtValueRemoved);
  event LogDeposit(
    address indexed user,
    address indexed vaultToken,
    address stableToken,
    uint256 stableAmountDeposited
  );
  // todo: add fields
  event LogWithdraw(
    address indexed user,
    address indexed vaultToken,
    uint256 burnedAmount,
    address stableToken,
    uint256 stableAmountToUser,
    uint256 assetAmountToUser
  );

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
