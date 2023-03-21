// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

library LibLYFConstant {
  enum AssetTier {
    UNLISTED,
    COLLATERAL,
    LP
  }
  uint256 internal constant MAX_BPS = 10000;

  struct TokenConfig {
    LibLYFConstant.AssetTier tier;
    uint16 collateralFactor;
    uint16 borrowingFactor;
    uint64 to18ConversionFactor;
    uint256 maxCollateral;
  }

  struct LPConfig {
    address strategy;
    address masterChef;
    address router;
    address rewardToken;
    address[] reinvestPath;
    uint256 poolId;
    uint256 reinvestThreshold;
    uint256 maxLpAmount;
    uint256 reinvestTreasuryBountyBps;
  }

  struct DebtPoolInfo {
    address token;
    address interestModel;
    uint256 totalShare;
    uint256 totalValue;
    uint256 lastAccruedAt;
  }

  struct RewardConversionConfig {
    address router;
    address[] path;
  }
}
