// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

library LibAVConstant {
  enum AssetTier {
    TOKEN,
    LP
  }

  struct VaultConfig {
    uint8 leverageLevel;
    uint16 managementFeePerSec;
    address vaultToken;
    address lpToken;
    address stableToken;
    address assetToken;
    address stableTokenInterestModel;
    address assetTokenInterestModel;
    address handler;
  }

  struct TokenConfig {
    AssetTier tier;
    uint64 to18ConversionFactor;
  }

  uint256 internal constant MAX_BPS = 10000;
}
