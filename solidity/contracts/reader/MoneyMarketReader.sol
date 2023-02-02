// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// ---- External Libraries ---- //
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// ---- Libraries ---- //
import { LibMoneyMarket01 } from "../money-market/libraries/LibMoneyMarket01.sol";

// ---- Interfaces ---- //
import { IMoneyMarket } from "./interfaces/IMoneyMarket.sol";
import { IInterestBearingToken } from "./interfaces/IInterestBearingToken.sol";

contract MoneyMarketReader is Ownable {
  IMoneyMarket private _moneyMarket;

  struct ReaderSummary {
    // ---- IBToken ---- //
    uint256 ibTotalSupply;
    uint256 ibTotalAsset;
    address ibAddress;

    // ---- Money Market ---- //
    LibMoneyMarket01.TokenConfig tokenConfig;
    uint256 globalDebtValueWithPendinthInterest;
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

  /// @dev 
  /// @param _underlyingToken The underlying token address
  function getReaderSummary(address _underlyingToken) external view returns (ReaderSummary memory _readerSummary) {
    address _ibAddres = _moneyMarket.getIbTokenFromToken(_underlyingToken);
    IInterestBearingToken _ibToken = IInterestBearingToken(_ibAddres);

    return ReaderSummary({
      ibTotalSupply: _ibToken.totalSupply(),
      ibTotalAsset: _ibToken.totalAssets(),
      ibAddress: _ibAddres,
      tokenConfig: _moneyMarket.getTokenConfig(_underlyingToken),
      globalDebtValueWithPendinthInterest: _moneyMarket.getGlobalDebtValueWithPendingInterest(_underlyingToken),
      globalDebtValue: _moneyMarket.getGlobalDebtValue(_underlyingToken) ,
      pendingIntetest: _moneyMarket.getGlobalPendingInterest(_underlyingToken),
      lastAccruedAt: _moneyMarket.getDebtLastAccruedAt(_underlyingToken),
      allocPoint: 0,
      totalAllocPoint: 0,
      rewardPerSec: 0,
      blockTimestamp: block.timestamp
    });
  }
}