// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

library LibLYFConstant {
  enum AssetTier {
    UNLISTED,
    COLLATERAL,
    LP
  }
  uint256 internal constant MAX_BPS = 10000;
}
