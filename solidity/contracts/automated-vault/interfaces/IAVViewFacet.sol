// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface IAVViewFacet {
  function getDebtValues(address _vaultToken) external view returns (uint256 _stableDebtValue, uint256 _assetDebtValue);

  function getPendingInterest(address _vaultToken)
    external
    view
    returns (uint256 _stablePendingInterest, uint256 _assetPendingInterest);

  function getLastAccrueInterestTimestamp(address _vaultToken) external view returns (uint256);

  function getPendingManagementFee(address _vaultToken) external view returns (uint256 _pendingManagementFee);
}
