// SPDX-License-Identifier: BUSL
pragma solidity >=0.8.19;

library LibConstant {
  enum AssetTier {
    UNLISTED,
    ISOLATE,
    CROSS,
    COLLATERAL
  }

  struct TokenConfig {
    AssetTier tier;
    uint16 collateralFactor;
    uint16 borrowingFactor;
    uint64 to18ConversionFactor;
    uint256 maxCollateral;
    uint256 maxBorrow; // shared global limit
  }

  uint256 internal constant MAX_BPS = 10000;
}
