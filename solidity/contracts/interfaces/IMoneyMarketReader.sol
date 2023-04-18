// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface IMoneyMarketReader {
  struct MarketSummary {
    // ---- ibToken ---- //
    uint256 ibTotalSupply;
    uint256 ibTotalAsset;
    address ibAddress;
    uint16 ibCollateralFactor;
    uint16 ibBorrowingFactor;
    // ---- Token Config ---- //
    uint8 tierAsUInt;
    uint16 collateralFactor;
    uint16 borrowingFactor;
    uint64 to18ConversionFactor;
    uint256 maxCollateral;
    uint256 maxBorrow;
    uint256 tokenPrice;
    // ---- Money Market ---- //
    uint256 globalDebtValue;
    uint256 totalToken;
    uint256 pendingIntetest;
    uint256 lastAccruedAt;
    // ---- MiniFL ---- //
    uint256 debtTokenAllocPoint;
    uint256 ibTokenAllocPoint;
    uint256 totalAllocPoint;
    uint256 rewardPerSec;
    uint256 totalDebtTokenInPool;
    uint256 totalUnderlyingTokenInPool;
    uint256 blockTimestamp;
  }

  struct CollateralPosition {
    address ibToken;
    address underlyingToken;
    uint256 amount;
    uint256 ibTokenPrice;
    uint256 underlyingTokenPrice;
    uint16 collateralFactor;
  }
  struct DebtPosition {
    address token;
    uint256 shares;
    uint256 amount;
    uint256 price;
    uint16 borrowingFactor;
  }

  struct SubAccountSummary {
    uint256 subAccountId;
    uint256 totalBorrowedValue;
    uint256 totalCollateralValue;
    uint256 totalBorrowingPower;
    uint256 totalUsedBorrowingPower;
    CollateralPosition[] collaterals;
    DebtPosition[] debts;
  }

  struct SupplyAccountDetail {
    address ibTokenAddress;
    address underlyingToken;
    // Amount staked in MiniFL by AccountManager
    uint256 supplyIbAmount;
    uint256 ibTokenPrice;
    // Amount of underlyingToken converted from ibToken amount
    uint256 underlyingAmount;
    uint256 underlyingTokenPrice;
  }

  struct MainAccountSummary {
    SupplyAccountDetail[] supplyAccountDetails;
  }

  struct RewardSummary {
    uint256 ibPoolId;
    uint256 debtPoolId;
    uint256 lendingPendingReward;
    uint256 borrowingPendingReward;
  }

  function getMarketSummary(address _underlyingToken) external view returns (MarketSummary memory);

  function getRewardSummary(address _underlyingToken, address _account) external view returns (RewardSummary memory);

  function getSubAccountSummary(address _account, uint256 _subAccountId)
    external
    view
    returns (SubAccountSummary memory);

  function getMainAccountSummary(address _account, address[] calldata _underlyingTokenAddresses)
    external
    view
    returns (MainAccountSummary memory _mainAccountSummary);

  function moneyMarket() external view returns (address);

  function getPriceUSD(address _token) external view returns (uint256);

  function getPrice(address _token0, address _token1) external view returns (uint256);

  struct TokenConfig {
    uint8 tier;
    uint16 collateralFactor;
    uint16 borrowingFactor;
    uint256 maxCollateral;
    uint256 maxBorrow;
  }

  struct MarketMetadata {
    address underlyingTokenAddress;
    address ibTokenAddress;
    TokenConfig underlyingTokenConfig;
    TokenConfig ibTokenConfig;
  }

  function getMarketMetadata(address _underlyingToken) external view returns (MarketMetadata memory);

  struct MarketStats {
    uint256 ibTotalSupply;
    uint256 ibTotalAsset;
    uint256 globalDebtValue;
    uint256 reserve;
    uint256 totalToken;
    uint256 pendingIntetest;
    uint256 interestRate;
    uint256 lastAccruedAt;
    uint256 blockTimestamp;
  }

  function getMarketStats(address _underlyingToken) external view returns (MarketStats memory);

  struct MarketRewardInfo {
    uint256 debtTokenAllocPoint;
    uint256 ibTokenAllocPoint;
    uint256 totalAllocPoint;
    uint256 rewardPerSec;
    uint256 totalDebtTokenInPool;
    uint256 totalUnderlyingTokenInPool;
  }

  function getMarketRewardInfo(address _underlyingToken) external view returns (MarketRewardInfo memory);

  struct MarketPriceInfo {
    uint256 underlyingTokenPrice;
    uint256 ibTokenPrice;
    uint256 underlyingToIbRate;
  }

  function getMarketPriceInfo(address _underlyingToken) external view returns (MarketPriceInfo memory);

  struct TripleSlopeModelConfig {
    uint256 ceilSlope1;
    uint256 ceilSlope2;
    uint256 ceilSlope3;
    uint256 maxInterestSlope1;
    uint256 maxInterestSlope2;
    uint256 maxInterestSlope3;
  }

  function getInterestRateModelConfig(address _underlyingToken) external view returns (TripleSlopeModelConfig memory);
}
