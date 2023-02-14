// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface IMoneyMarketReader {
  struct MarketSummary {
    // ---- ibToken ---- //
    uint256 ibTotalSupply;
    uint256 ibTotalAsset;
    address ibAddress;
    // ---- Token Config ---- //
    uint8 tierAsUInt;
    uint16 collateralFactor;
    uint16 borrowingFactor;
    uint64 to18ConversionFactor;
    uint256 maxCollateral;
    uint256 maxBorrow;
    // ---- Money Market ---- //
    uint256 globalDebtValue;
    uint256 totalToken;
    uint256 pendingIntetest;
    uint256 lastAccruedAt;
    // ---- MiniFL ---- //
    uint256 allocPoint;
    uint256 totalAllocPoint;
    uint256 rewardPerSec;
    uint256 blockTimestamp;
  }

  function getMarketSummary(address _underlyingToken) external view returns (MarketSummary memory);

  function moneyMarket() external view returns (address);
}
