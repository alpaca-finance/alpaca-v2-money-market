// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// interfaces
import { IAVViewFacet } from "../interfaces/IAVViewFacet.sol";

// interfaces
import { IERC20 } from "../interfaces/IERC20.sol";

// libraries
import { LibAV01 } from "../libraries/LibAV01.sol";
import { LibAVConstant } from "../libraries/LibAVConstant.sol";

contract AVViewFacet is IAVViewFacet {
  function getDebtValues(address _vaultToken)
    external
    view
    returns (uint256 _stableDebtValue, uint256 _assetDebtValue)
  {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();
    LibAVConstant.VaultConfig memory _config = avDs.vaultConfigs[_vaultToken];
    _stableDebtValue = avDs.vaultDebts[_vaultToken][_config.stableToken];
    _assetDebtValue = avDs.vaultDebts[_vaultToken][_config.assetToken];
  }

  function getPendingInterest(address _vaultToken)
    external
    view
    returns (uint256 _stablePendingInterest, uint256 _assetPendingInterest)
  {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();
    uint256 _timeSinceLastAccrual = block.timestamp - avDs.lastAccrueInterestTimestamps[_vaultToken];

    if (_timeSinceLastAccrual > 0) {
      LibAVConstant.VaultConfig memory vaultConfig = avDs.vaultConfigs[_vaultToken];
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

  function getLastAccrueInterestTimestamp(address _vaultToken) external view returns (uint256) {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();
    return avDs.lastAccrueInterestTimestamps[_vaultToken];
  }

  function getPendingManagementFee(address _vaultToken) external view returns (uint256 _pendingManagementFee) {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();
    _pendingManagementFee =
      (IERC20(_vaultToken).totalSupply() *
        avDs.vaultConfigs[_vaultToken].managementFeePerSec *
        (block.timestamp - avDs.lastFeeCollectionTimestamps[_vaultToken])) /
      1e18;
  }
}
