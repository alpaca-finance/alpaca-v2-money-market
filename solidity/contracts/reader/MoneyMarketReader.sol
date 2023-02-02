// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// ---- Libraries ---- //
import { LibMoneyMarket01 } from "../money-market/libraries/LibMoneyMarket01.sol";

// ---- Interfaces ---- //
import { IMoneyMarket } from "../money-market/interfaces/IMoneyMarket.sol";
import { IInterestBearingToken } from "../money-market/interfaces/IInterestBearingToken.sol";

contract MoneyMarketReader {
  IMoneyMarket private _moneyMarket;

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
    uint256 pendingIntetest;
    uint256 lastAccruedAt;
    // ---- MiniFL ---- //
    uint256 allocPoint;
    uint256 totalAllocPoint;
    uint256 rewardPerSec;
    uint256 blockTimestamp;
  }

  constructor(address moneyMarket_) {
    _moneyMarket = IMoneyMarket(moneyMarket_);
  }

  /// @dev Get the market summary
  /// @param _underlyingToken The underlying token address
  function getMarketSummary(address _underlyingToken) external view returns (MarketSummary memory) {
    address _ibAddress = _moneyMarket.getIbTokenFromToken(_underlyingToken);
    IInterestBearingToken _ibToken = IInterestBearingToken(_ibAddress);

    LibMoneyMarket01.TokenConfig memory _tokenConfig = _moneyMarket.getTokenConfig(_underlyingToken);

    return
      MarketSummary({
        ibTotalSupply: _ibToken.totalSupply(),
        ibTotalAsset: _ibToken.totalAssets(),
        ibAddress: _ibAddress,
        tierAsUInt: uint8(_tokenConfig.tier),
        collateralFactor: _tokenConfig.collateralFactor,
        borrowingFactor: _tokenConfig.borrowingFactor,
        to18ConversionFactor: _tokenConfig.to18ConversionFactor,
        maxCollateral: _tokenConfig.maxCollateral,
        maxBorrow: _tokenConfig.maxBorrow,
        globalDebtValue: _moneyMarket.getGlobalDebtValue(_underlyingToken),
        pendingIntetest: _moneyMarket.getGlobalPendingInterest(_underlyingToken),
        lastAccruedAt: _moneyMarket.getDebtLastAccruedAt(_underlyingToken),
        allocPoint: 0,
        totalAllocPoint: 0,
        rewardPerSec: 0,
        blockTimestamp: block.timestamp
      });
  }
}
