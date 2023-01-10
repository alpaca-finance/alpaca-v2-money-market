// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface IAVViewFacet {
  function getDebtValues(address _shareToken) external view returns (uint256, uint256);

  function getPendingInterest(address _vaultToken)
    external
    view
    returns (uint256 _stablePendingInterest, uint256 _assetPendingInterest);

  function getLastAccrueInterestTimestamp(address _vaultToken) external view returns (uint256);

  function getPendingManagementFee(address _shareToken) external view returns (uint256 _pendingManagementFee);
}
