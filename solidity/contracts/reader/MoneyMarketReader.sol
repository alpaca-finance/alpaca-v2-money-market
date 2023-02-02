// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// ---- Libraries ---- //
import { LibMoneyMarket01 } from "../money-market/libraries/LibMoneyMarket01.sol";

// ---- Interfaces ---- //
import { IMoneyMarket } from "./interfaces/IMoneyMarket.sol";
import { IInterestBearingToken } from "./interfaces/IInterestBearingToken.sol";

contract MoneyMarketReader {
  IMoneyMarket private _moneyMarket;

  struct MarketSummary {
    // ---- IBToken ---- //
    uint256 ibTotalSupply;
    uint256 ibTotalAsset;
    address ibAddress;
    // ---- Money Market ---- //
    LibMoneyMarket01.TokenConfig tokenConfig;
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

    return
      MarketSummary({
        ibTotalSupply: _ibToken.totalSupply(),
        ibTotalAsset: _ibToken.totalAssets(),
        ibAddress: _ibAddress,
        tokenConfig: _moneyMarket.getTokenConfig(_underlyingToken),
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
