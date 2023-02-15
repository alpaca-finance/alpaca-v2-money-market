// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// ---- Libraries ---- //
import { LibMoneyMarket01 } from "../money-market/libraries/LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "../money-market/libraries/LibDoublyLinkedList.sol";

// ---- Interfaces ---- //
import { IMoneyMarketReader } from "../interfaces/IMoneyMarketReader.sol";
import { IMoneyMarket } from "../money-market/interfaces/IMoneyMarket.sol";
import { IInterestBearingToken } from "../money-market/interfaces/IInterestBearingToken.sol";
import { IPriceOracle } from "../oracle/interfaces/IPriceOracle.sol";
import { IAlpacaV2Oracle } from "../oracle/interfaces/IAlpacaV2Oracle.sol";

contract MoneyMarketReader is IMoneyMarketReader {
  IMoneyMarket private _moneyMarket;

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
        tokenPrice: _getPrice(IPriceOracle(address(0)), _underlyingToken, address(0)),
        globalDebtValue: _moneyMarket.getGlobalDebtValue(_underlyingToken),
        totalToken: _moneyMarket.getTotalToken(_underlyingToken),
        pendingIntetest: _moneyMarket.getGlobalPendingInterest(_underlyingToken),
        lastAccruedAt: _moneyMarket.getDebtLastAccruedAt(_underlyingToken),
        allocPoint: 0,
        totalAllocPoint: 0,
        rewardPerSec: 0,
        blockTimestamp: block.timestamp
      });
  }

  function getSubAccountSummary(address _account, uint256 _subAccountId)
    external
    view
    returns (SubAccountSummary memory summary)
  {
    // IAlpacaV2Oracle _alpacaV2Oracle = IAlpacaV2Oracle(_moneyMarket.getOracle());
    // IPriceOracle _oracleMedianizer = IPriceOracle(_alpacaV2Oracle.oracle());
    // address _usd = _alpacaV2Oracle.usd();
    IPriceOracle _oracleMedianizer;
    address _usd;

    CollateralPosition[] memory _collaterals;
    DebtPosition[] memory _debts;

    uint256 _tmpVal;
    address _token;
    uint256 _price;

    {
      LibDoublyLinkedList.Node[] memory _rawCollats = _moneyMarket.getAllSubAccountCollats(_account, _subAccountId);
      uint256 _collatLen = _rawCollats.length;
      _collaterals = new CollateralPosition[](_collatLen);
      for (uint256 _i; _i < _collatLen; ) {
        _token = _rawCollats[_i].token;
        _price = _getPrice(_oracleMedianizer, _token, _usd);
        LibMoneyMarket01.TokenConfig memory _tokenConfig = _moneyMarket.getTokenConfig(_token);

        _tmpVal = (_price * _rawCollats[_i].amount * _tokenConfig.to18ConversionFactor) / 1e18;
        summary.totalCollateralValue += _tmpVal;
        summary.totalBorrowingPower += (_tmpVal * _tokenConfig.collateralFactor) / LibMoneyMarket01.MAX_BPS;

        _collaterals[_i] = CollateralPosition({
          token: _token,
          amount: _rawCollats[_i].amount,
          price: _price,
          collateralFactor: _tokenConfig.collateralFactor
        });

        unchecked {
          ++_i;
        }
      }
    }

    {
      LibDoublyLinkedList.Node[] memory _rawDebts = _moneyMarket.getOverCollatDebtSharesOf(_account, _subAccountId);
      uint256 _debtLen = _rawDebts.length;
      _debts = new DebtPosition[](_debtLen);
      for (uint256 _i; _i < _debtLen; ) {
        _token = _rawDebts[_i].token;
        _price = _getPrice(_oracleMedianizer, _token, _usd);
        LibMoneyMarket01.TokenConfig memory _tokenConfig = _moneyMarket.getTokenConfig(_token);
        (uint256 _totalDebtShares, uint256 _totalDebtAmount) = _moneyMarket.getOverCollatTokenDebt(_token);

        _tmpVal = (_price * _rawDebts[_i].amount * _tokenConfig.to18ConversionFactor) / 1e18;
        summary.totalBorrowedValue += _tmpVal;
        summary.totalUsedBorrowingPower += (_tmpVal * LibMoneyMarket01.MAX_BPS) / _tokenConfig.borrowingFactor;

        _debts[_i] = DebtPosition({
          token: _token,
          shares: _rawDebts[_i].amount,
          amount: (_rawDebts[_i].amount * _totalDebtAmount) / _totalDebtShares,
          price: _price,
          borrowingFactor: _tokenConfig.borrowingFactor
        });

        unchecked {
          ++_i;
        }
      }
    }

    summary.collaterals = _collaterals;
    summary.debts = _debts;
  }

  // /// @dev Return the price of token0/token1, multiplied by 1e18
  // function getPrice(address token0, address token1) external view returns (uint256, uint256) {
  //   IAlpacaV2Oracle _alpacaV2Oracle = IAlpacaV2Oracle(_moneyMarket.getOracle());
  //   IPriceOracle _oracleMedianizer = IPriceOracle(_alpacaV2Oracle.oracle());
  //   return (_getPrice(_oracleMedianizer, token0, token1), block.timestamp);
  // }

  // function getPriceUSD(address token) external view returns (uint256, uint256)

  /// @dev use mock until deploy real oracle
  function _getPrice(
    IPriceOracle, /* oracle */
    address token0,
    address /* token1 */
  ) internal view returns (uint256 price) {
    (price, ) = IAlpacaV2Oracle(_moneyMarket.getOracle()).getTokenPrice(token0);
  }

  // TODO: use real oracle
  // /// @dev partially replicate `OracleMedianizer.getPrice` logic
  // ///      differences from original implementation
  // ///      1) doesn't revert on no primary or valid source, returns 0 instead
  // ///      2) ignore price deviation, instead returns
  // ///        - the only valid price in case of 1 valid source
  // ///        - average price in case of 2 valid sources
  // ///        - median price in case of 3 valid sources
  // ///      this was modified to not revert for viewing purpose
  // ///      any error on price validity should be handled separately by presentation layer
  // ///
  // /// @return `token0Price / token1Price` in 18 decimals
  // ///         for 1 valid source, returns the only valid price
  // ///         for 2 valid sources, returns average of 2 valid price
  // ///         for 3 valid sources, returns median price
  // ///         return 0 upon no primary or valid source
  // function _getPrice(
  //   IPriceOracle oracle,
  //   address token0,
  //   address token1
  // ) internal view returns (uint256) {
  //   uint256 candidateSourceCount = oracle.primarySourceCount(token0, token1);
  //   if (candidateSourceCount == 0) return 0;

  //   uint256[] memory prices = new uint256[](candidateSourceCount);
  //   // Get price from valid oracle sources
  //   uint256 validSourceCount;
  //   for (uint256 idx; idx < candidateSourceCount; ) {
  //     try oracle.primarySources(token0, token1, idx).getPrice(token0, token1) returns (
  //       uint256 price,
  //       uint256 /* lastUpdate */
  //     ) {
  //       unchecked {
  //         // ignore price stale
  //         prices[validSourceCount++] = price;
  //         ++idx;
  //       }
  //     } catch {}
  //   }
  //   if (validSourceCount == 0) return 0;

  //   // Sort prices (asc)
  //   for (uint256 _i; _i < validSourceCount - 1; ) {
  //     for (uint256 _j; _j < validSourceCount - _i - 1; ) {
  //       if (prices[_j] > prices[_j + 1]) {
  //         (prices[_j], prices[_j + 1]) = (prices[_j + 1], prices[_j]);
  //       }
  //       unchecked {
  //         ++_j;
  //       }
  //     }
  //     unchecked {
  //       ++_i;
  //     }
  //   }

  //   // ignore price deviation
  //   if (validSourceCount == 1) return prices[0]; // if 1 valid source, return price
  //   if (validSourceCount == 2) {
  //     return (prices[0] + prices[1]) / 2; // if 2 valid sources, return average
  //   }
  //   return prices[1]; // if 3 valid sources, return median
  // }

  function moneyMarket() external view returns (address) {
    return address(_moneyMarket);
  }
}
