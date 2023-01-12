// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { LibAV01 } from "../libraries/LibAV01.sol";

interface IAVAdminFacet {
  struct ShareTokenPairs {
    address token;
    address shareToken;
  }

  struct VaultConfigInput {
    address shareToken;
    address lpToken;
    address stableToken;
    address assetToken;
    address stableTokenInterestModel;
    address assetTokenInterestModel;
    uint8 leverageLevel;
    uint16 managementFeePerSec;
  }

  struct TokenConfigInput {
    LibAV01.AssetTier tier;
    address token;
  }

  error AVTradeFacet_InvalidToken(address _token);
  error AVAdminFacet_InvalidShareToken(address _token);
  error AVAdminFacet_InvalidHandler();

  event LogOpenVault(
    address indexed _caller,
    address indexed _lpToken,
    address _stableToken,
    address _assetToken,
    address _shareToken
  );

  function openVault(
    address _lpToken,
    address _stableToken,
    address _assetToken,
    address _handler,
    uint8 _leverageLevel,
    uint16 _managementFeePerSec,
    address _stableTokenInterestModel,
    address _assetTokenInterestModel
  ) external returns (address _newShareToken);

  function setTokenConfigs(TokenConfigInput[] calldata configs) external;

  function setMoneyMarket(address _newMoneyMarket) external;

  function setOracle(address _oracle) external;

  function setTreasury(address _treasury) external;

  function setManagementFeePerSec(address _vaultToken, uint16 _newManagementFeePerSec) external;

  function setInterestRateModels(
    address _vaultToken,
    address _newStableTokenInterestRateModel,
    address _newAssetTokenInterestRateModel
  ) external;
}
