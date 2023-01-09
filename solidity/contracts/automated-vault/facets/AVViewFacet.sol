// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// interfaces
import { IAVViewFacet } from "../interfaces/IAVViewFacet.sol";

// libraries
import { LibAV01 } from "../libraries/LibAV01.sol";

contract AVViewFacet is IAVViewFacet {
  function getDebtValues(address _shareToken) external view returns (uint256, uint256) {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();
    LibAV01.VaultConfig memory _config = avDs.vaultConfigs[_shareToken];
    return (avDs.vaultDebts[_shareToken][_config.stableToken], avDs.vaultDebts[_shareToken][_config.assetToken]);
  }

  function getVaultPendingInterest(address _vaultToken)
    external
    view
    returns (uint256 _stablePendingInterest, uint256 _assetPendingInterest)
  {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();
    uint256 _timeSinceLastAccrual = block.timestamp - avDs.lastAccrueInterestTimestamps[_vaultToken];

    if (_timeSinceLastAccrual > 0) {
      LibAV01.VaultConfig memory vaultConfig = avDs.vaultConfigs[_vaultToken];
      address _moneyMarket = avDs.moneyMarket;

      _stablePendingInterest = LibAV01.getTokenPendingInterest(
        _vaultToken,
        _moneyMarket,
        vaultConfig.stableToken,
        vaultConfig.stableTokenInterestModel,
        _timeSinceLastAccrual,
        avDs
      );
      _assetPendingInterest = LibAV01.getTokenPendingInterest(
        _vaultToken,
        _moneyMarket,
        vaultConfig.assetToken,
        vaultConfig.assetTokenInterestModel,
        _timeSinceLastAccrual,
        avDs
      );
    }
  }

  function getVaultLastAccrueInterestTimestamp(address _vaultToken) external view returns (uint256) {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();
    return avDs.lastAccrueInterestTimestamps[_vaultToken];
  }

  function getPendingManagementFee(address _shareToken) external view returns (uint256 _pendingManagementFee) {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();
    _pendingManagementFee = LibAV01.getPendingManagementFee(_shareToken, avDs);
  }
}
