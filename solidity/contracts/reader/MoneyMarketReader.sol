// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// ---- Libraries ---- //
import { LibMoneyMarket01 } from "../money-market/libraries/LibMoneyMarket01.sol";
import { LibConstant } from "../money-market/libraries/LibConstant.sol";
import { LibDoublyLinkedList } from "../money-market/libraries/LibDoublyLinkedList.sol";

// ---- Interfaces ---- //
import { IMoneyMarketReader } from "../interfaces/IMoneyMarketReader.sol";
import { IMoneyMarket } from "../money-market/interfaces/IMoneyMarket.sol";
import { IInterestBearingToken } from "../money-market/interfaces/IInterestBearingToken.sol";
import { IOracleMedianizer } from "../oracle/interfaces/IOracleMedianizer.sol";
import { IAlpacaV2Oracle } from "../oracle/interfaces/IAlpacaV2Oracle.sol";
import { IMiniFL } from "../money-market/interfaces/IMiniFL.sol";
import { IInterestRateModel } from "../money-market/interfaces/IInterestRateModel.sol";
import { IRewarder } from "../miniFL/interfaces/IRewarder.sol";

contract MoneyMarketReader is IMoneyMarketReader {
  IMoneyMarket private immutable _moneyMarket;
  IMiniFL private immutable _miniFL;
  address private immutable _moneyMarketAccountManager;
  address private constant USD = 0x115dffFFfffffffffFFFffffFFffFfFfFFFFfFff;

  constructor(address moneyMarket_, address moneyMarketAccountManager_) {
    _moneyMarket = IMoneyMarket(moneyMarket_);
    _miniFL = IMiniFL(_moneyMarket.getMiniFL());
    _moneyMarketAccountManager = moneyMarketAccountManager_;
  }

  /// @dev Get the reward summary
  /// @param _pId Pool id of miniFL
  /// @param _account The account address
  /// @param _rewarders List of rewarder addresses associate with miniFL pId
  function getRewardSummary(
    uint256 _pId,
    address _account,
    address[] calldata _rewarders
  ) external view returns (RewardSummary[] memory _rewardSummary) {
    // include miniFL reward
    uint256 _rewardLength = _rewarders.length + 1;
    _rewardSummary = new RewardSummary[](_rewardLength);

    _rewardSummary[0] = RewardSummary({
      rewardToken: _miniFL.ALPACA(),
      pId: _pId,
      pendingReward: _miniFL.pendingAlpaca(_pId, _account)
    });

    for (uint256 i; i < _rewarders.length; ) {
      IRewarder _rewarder = IRewarder(_rewarders[i]);

      _rewardSummary[i + 1] = RewardSummary({
        rewardToken: _rewarder.rewardToken(),
        pId: _pId,
        pendingReward: _rewarder.pendingToken(_pId, _account)
      });
      unchecked {
        ++i;
      }
    }
  }

  /// @dev Get subaccount summary of collaterals and debts
  function getSubAccountSummary(address _account, uint256 _subAccountId)
    external
    view
    returns (SubAccountSummary memory summary)
  {
    summary.subAccountId = _subAccountId;

    (summary.totalCollateralValue, summary.totalBorrowingPower, summary.collaterals) = _getSubAccountCollatSummary(
      _account,
      _subAccountId
    );
    (summary.totalBorrowedValue, summary.totalUsedBorrowingPower, summary.debts) = _getSubAccountDebtSummary(
      _account,
      _subAccountId
    );
  }

  /// @dev Get supply account summary
  function getMainAccountSummary(address _account, address[] calldata _underlyingTokenAddresses)
    external
    view
    returns (MainAccountSummary memory _mainAccountSummary)
  {
    uint256 marketLength = _underlyingTokenAddresses.length;

    SupplyAccountDetail[] memory _supplyAccountDetails = new SupplyAccountDetail[](marketLength);
    address _underlyingTokenAddress;

    for (uint256 _i; _i < marketLength; _i++) {
      _underlyingTokenAddress = _underlyingTokenAddresses[_i];

      _supplyAccountDetails[_i] = _getSupplyAccountDetail(_account, _underlyingTokenAddress);
    }

    _mainAccountSummary = MainAccountSummary({ supplyAccountDetails: _supplyAccountDetails });
  }

  function _getSupplyAccountDetail(address _account, address _underlyingTokenAddress)
    internal
    view
    returns (SupplyAccountDetail memory _supplyAccountDetail)
  {
    address _ibTokenAddress = _moneyMarket.getIbTokenFromToken(_underlyingTokenAddress);
    uint256 _pid = _moneyMarket.getMiniFLPoolIdOfToken(_ibTokenAddress);
    uint256 _supplyIbAmount = _miniFL.getUserAmountFundedBy(_moneyMarketAccountManager, _account, _pid);

    _supplyAccountDetail = SupplyAccountDetail({
      ibTokenAddress: _ibTokenAddress,
      underlyingToken: _underlyingTokenAddress,
      supplyIbAmount: _supplyIbAmount,
      ibTokenPrice: _getPriceUSD(_ibTokenAddress),
      underlyingAmount: IInterestBearingToken(_ibTokenAddress).convertToAssets(_supplyIbAmount),
      underlyingTokenPrice: _getPriceUSD(_underlyingTokenAddress)
    });
  }

  function _getSubAccountCollatSummary(address _account, uint256 _subAccountId)
    internal
    view
    returns (
      uint256 _totalCollateralValue,
      uint256 _totalBorrowingPower,
      CollateralPosition[] memory _collaterals
    )
  {
    LibDoublyLinkedList.Node[] memory _rawCollats = _moneyMarket.getAllSubAccountCollats(_account, _subAccountId);
    uint256 _collatLen = _rawCollats.length;
    _collaterals = new CollateralPosition[](_collatLen);

    // currently only accept ib as collateral
    // if there is non-ib collat it would revert because get price for address 0
    for (uint256 _i; _i < _collatLen; ++_i) {
      address _ibToken = _rawCollats[_i].token;
      address _underlyingToken = _moneyMarket.getTokenFromIbToken(_ibToken);

      uint256 _ibTokenPrice = _getPriceUSD(_ibToken);
      uint256 _underlyingTokenPrice = _getPriceUSD(_underlyingToken);
      LibConstant.TokenConfig memory _tokenConfig = _moneyMarket.getTokenConfig(_ibToken);

      uint256 _valueUSD = (_ibTokenPrice * _rawCollats[_i].amount * _tokenConfig.to18ConversionFactor) / 1e18;
      _totalCollateralValue += _valueUSD;
      _totalBorrowingPower += (_valueUSD * _tokenConfig.collateralFactor) / LibConstant.MAX_BPS;

      _collaterals[_i] = CollateralPosition({
        ibToken: _ibToken,
        underlyingToken: _underlyingToken,
        amount: _rawCollats[_i].amount,
        ibTokenPrice: _ibTokenPrice,
        underlyingTokenPrice: _underlyingTokenPrice,
        collateralFactor: _tokenConfig.collateralFactor
      });
    }
  }

  function _getSubAccountDebtSummary(address _account, uint256 _subAccountId)
    internal
    view
    returns (
      uint256 _totalBorrowedValue,
      uint256 _totalUsedBorrowingPower,
      DebtPosition[] memory _debts
    )
  {
    LibDoublyLinkedList.Node[] memory _rawDebts = _moneyMarket.getOverCollatDebtSharesOf(_account, _subAccountId);
    uint256 _debtLen = _rawDebts.length;
    _debts = new DebtPosition[](_debtLen);

    for (uint256 _i; _i < _debtLen; ++_i) {
      address _token = _rawDebts[_i].token;
      uint256 _price = _getPriceUSD(_token);
      LibConstant.TokenConfig memory _tokenConfig = _moneyMarket.getTokenConfig(_token);
      (uint256 _totalDebtShares, uint256 _totalDebtAmount) = _moneyMarket.getOverCollatTokenDebt(_token);

      uint256 _actualDebtAmount = (_rawDebts[_i].amount *
        (_totalDebtAmount + _moneyMarket.getOverCollatPendingInterest(_token))) / _totalDebtShares;

      uint256 _valueUSD = (_price * _actualDebtAmount * _tokenConfig.to18ConversionFactor) / 1e18;
      _totalBorrowedValue += _valueUSD;
      _totalUsedBorrowingPower += (_valueUSD * LibConstant.MAX_BPS) / _tokenConfig.borrowingFactor;

      _debts[_i] = DebtPosition({
        token: _token,
        shares: _rawDebts[_i].amount,
        amount: _actualDebtAmount,
        price: _price,
        borrowingFactor: _tokenConfig.borrowingFactor
      });
    }
  }

  /// @dev Return the price of token0/token1, multiplied by 1e18
  function getPrice(address _token0, address _token1) public view returns (uint256) {
    IAlpacaV2Oracle _alpacaV2Oracle = IAlpacaV2Oracle(_moneyMarket.getOracle());
    IOracleMedianizer _oracleMedianizer = IOracleMedianizer(_alpacaV2Oracle.oracle());
    return _getPrice(_oracleMedianizer, _token0, _token1);
  }

  /// @dev Simply forward calling _getPriceUSD
  function getPriceUSD(address _token) external view returns (uint256) {
    return _getPriceUSD(_token);
  }

  /// @dev Return the price of `_token` in USD with 18 decimal places
  function _getPriceUSD(address _token) internal view returns (uint256) {
    IAlpacaV2Oracle _alpacaV2Oracle = IAlpacaV2Oracle(_moneyMarket.getOracle());
    IOracleMedianizer _oracleMedianizer = IOracleMedianizer(_alpacaV2Oracle.oracle());

    address _underlyingToken = _moneyMarket.getTokenFromIbToken(_token);
    // `_token` is ibToken
    if (_underlyingToken != address(0)) {
      return IInterestBearingToken(_token).convertToAssets(_getPrice(_oracleMedianizer, _underlyingToken, USD));
    }
    // not ibToken
    return _getPrice(_oracleMedianizer, _token, USD);
  }

  /// @dev for repurchase / liquidation test scenario
  // function _getPrice(
  //   IOracleMedianizer, /* oracle */
  //   address token0,
  //   address /* token1 */
  // ) internal view returns (uint256 _price) {
  //   (_price, ) = IAlpacaV2Oracle(_moneyMarket.getOracle()).getTokenPrice(token0);
  // }

  /// @dev partially replicate `OracleMedianizer.getPrice` logic
  ///      differences from original implementation
  ///      1) doesn't revert on no primary or valid source, returns 0 instead
  ///      2) ignore price deviation, instead returns
  ///        - the only valid price in case of 1 valid source
  ///        - average price in case of 2 valid sources
  ///        - median price in case of 3 valid sources
  ///      this was modified to not revert for viewing purpose
  ///      any error on price validity should be handled separately by presentation layer
  ///
  /// @return `token0Price / token1Price` in 18 decimals
  ///         for 1 valid source, returns the only valid price
  ///         for 2 valid sources, returns average of 2 valid price
  ///         for 3 valid sources, returns median price
  ///         return 0 upon no primary or valid source
  function _getPrice(
    IOracleMedianizer oracle,
    address token0,
    address token1
  ) internal view returns (uint256) {
    uint256 candidateSourceCount = oracle.primarySourceCount(token0, token1);
    if (candidateSourceCount == 0) return 0;

    uint256[] memory prices = new uint256[](candidateSourceCount);
    // Get price from valid oracle sources
    uint256 validSourceCount;
    for (uint256 idx; idx < candidateSourceCount; ) {
      try oracle.primarySources(token0, token1, idx).getPrice(token0, token1) returns (
        uint256 price,
        uint256 /* lastUpdate */
      ) {
        unchecked {
          // ignore price stale
          prices[validSourceCount++] = price;
        }
      } catch {}
      unchecked {
        ++idx;
      }
    }
    if (validSourceCount == 0) return 0;

    // Sort prices (asc)
    for (uint256 _i; _i < validSourceCount - 1; ) {
      for (uint256 _j; _j < validSourceCount - _i - 1; ) {
        if (prices[_j] > prices[_j + 1]) {
          (prices[_j], prices[_j + 1]) = (prices[_j + 1], prices[_j]);
        }
        unchecked {
          ++_j;
        }
      }
      unchecked {
        ++_i;
      }
    }

    // ignore price deviation
    if (validSourceCount == 1) return prices[0]; // if 1 valid source, return price
    if (validSourceCount == 2) {
      return (prices[0] + prices[1]) / 2; // if 2 valid sources, return average
    }
    return prices[1]; // if 3 valid sources, return median
  }

  function moneyMarket() external view returns (address) {
    return address(_moneyMarket);
  }

  function getMarketMetadata(address _underlyingToken) external view returns (MarketMetadata memory) {
    MarketMetadata memory marketMetadata;

    marketMetadata.underlyingTokenAddress = _underlyingToken;
    marketMetadata.ibTokenAddress = _moneyMarket.getIbTokenFromToken(_underlyingToken);

    LibConstant.TokenConfig memory _tokenConfig = _moneyMarket.getTokenConfig(_underlyingToken);
    marketMetadata.underlyingTokenConfig = TokenConfig({
      tier: uint8(_tokenConfig.tier),
      collateralFactor: _tokenConfig.collateralFactor,
      borrowingFactor: _tokenConfig.borrowingFactor,
      maxCollateral: _tokenConfig.maxCollateral,
      maxBorrow: _tokenConfig.maxBorrow
    });
    _tokenConfig = _moneyMarket.getTokenConfig(marketMetadata.ibTokenAddress);
    marketMetadata.ibTokenConfig = TokenConfig({
      tier: uint8(_tokenConfig.tier),
      collateralFactor: _tokenConfig.collateralFactor,
      borrowingFactor: _tokenConfig.borrowingFactor,
      maxCollateral: _tokenConfig.maxCollateral,
      maxBorrow: _tokenConfig.maxBorrow
    });

    return marketMetadata;
  }

  function getMarketStats(address _underlyingToken) external view returns (MarketStats memory) {
    MarketStats memory marketStats;

    IInterestBearingToken _ibToken = IInterestBearingToken(_moneyMarket.getIbTokenFromToken(_underlyingToken));

    marketStats.ibTotalSupply = _ibToken.totalSupply();
    marketStats.ibTotalAsset = _ibToken.totalAssets();
    marketStats.globalDebtValue = _moneyMarket.getGlobalDebtValue(_underlyingToken);
    marketStats.reserve = _moneyMarket.getFloatingBalance(_underlyingToken);
    marketStats.totalToken = _moneyMarket.getTotalToken(_underlyingToken);
    marketStats.pendingInterest = _moneyMarket.getGlobalPendingInterest(_underlyingToken);
    marketStats.interestRate = _moneyMarket.getOverCollatInterestRate(_underlyingToken);
    marketStats.lastAccruedAt = _moneyMarket.getDebtLastAccruedAt(_underlyingToken);
    marketStats.blockTimestamp = block.timestamp;

    return marketStats;
  }

  function getMarketRewardInfo(address _underlyingToken, address[] calldata _rewarders)
    external
    view
    returns (MarketRewardInfo memory)
  {
    address _ibAddress = _moneyMarket.getIbTokenFromToken(_underlyingToken);
    address _debtAddress = _moneyMarket.getDebtTokenFromToken(_underlyingToken);

    uint256 _ibPoolId = _moneyMarket.getMiniFLPoolIdOfToken(_ibAddress);
    uint256 _debtPoolId = _moneyMarket.getMiniFLPoolIdOfToken(_debtAddress);

    uint256 _ibReserveAmount = _miniFL.getStakingReserves(_ibPoolId);
    // debtTokenShare is equal to totalSupply of debtToken
    // then we can use debtTokenValue as total amount
    uint256 _totalDebtToken = _moneyMarket.getOverCollatTokenDebtValue(_underlyingToken) +
      _moneyMarket.getOverCollatPendingInterest(_underlyingToken);

    return
      MarketRewardInfo({
        totalUnderlyingTokenInPool: IInterestBearingToken(_ibAddress).convertToAssets(_ibReserveAmount),
        totalDebtTokenInPool: _totalDebtToken,
        ibRewarderInfos: _getRewardersInfo(_ibPoolId, _rewarders),
        debtRewarderInfos: _getRewardersInfo(_debtPoolId, _rewarders)
      });
  }

  function _getRewardersInfo(uint256 _pId, address[] calldata _rewarders)
    internal
    view
    returns (RewarderInfo[] memory _rewarderInfos)
  {
    uint256 rewarderLength = _rewarders.length + 1;
    _rewarderInfos = new RewarderInfo[](rewarderLength);

    _rewarderInfos[0] = RewarderInfo({
      rewardToken: _miniFL.ALPACA(),
      pId: _pId,
      rewardPerSec: _miniFL.alpacaPerSecond(),
      allocPoint: _miniFL.getPoolAllocPoint(_pId),
      totalAllocPoint: _miniFL.totalAllocPoint()
    });

    for (uint256 i; i < _rewarders.length; ) {
      IRewarder _rewarder = IRewarder(_rewarders[i]);

      _rewarderInfos[i + 1] = RewarderInfo({
        rewardToken: _rewarder.rewardToken(),
        pId: _pId,
        rewardPerSec: _rewarder.rewardPerSecond(),
        allocPoint: _rewarder.getPoolAllocPoint(_pId),
        totalAllocPoint: _rewarder.totalAllocPoint()
      });

      unchecked {
        ++i;
      }
    }
  }

  function getMarketPriceInfo(address _underlyingToken) external view returns (MarketPriceInfo memory) {
    MarketPriceInfo memory marketPriceInfo;

    IInterestBearingToken _ibToken = IInterestBearingToken(_moneyMarket.getIbTokenFromToken(_underlyingToken));

    marketPriceInfo.underlyingTokenPrice = _getPriceUSD(_underlyingToken);
    marketPriceInfo.underlyingToIbRate = _ibToken.convertToShares(1e18);
    marketPriceInfo.ibTokenPrice = _getPriceUSD(address(_ibToken));

    return marketPriceInfo;
  }

  function getInterestRateModelConfig(address _underlyingToken) external view returns (TripleSlopeModelConfig memory) {
    IInterestRateModel _interestRateModel = IInterestRateModel(
      _moneyMarket.getOverCollatInterestModel(_underlyingToken)
    );

    return
      TripleSlopeModelConfig({
        ceilSlope1: _interestRateModel.CEIL_SLOPE_1(),
        ceilSlope2: _interestRateModel.CEIL_SLOPE_2(),
        ceilSlope3: _interestRateModel.CEIL_SLOPE_3(),
        maxInterestSlope1: _interestRateModel.MAX_INTEREST_SLOPE_1(),
        maxInterestSlope2: _interestRateModel.MAX_INTEREST_SLOPE_2(),
        maxInterestSlope3: _interestRateModel.MAX_INTEREST_SLOPE_3()
      });
  }

  ///@dev Return the list of alpaca guard status of underlying tokens, true if alpaca guard is enabled
  function getAlpacaGuardStatuses(address[] calldata _underlyingTokens)
    external
    view
    returns (AlpacaGuardStatus[] memory _alpacaGuardStatuses)
  {
    IAlpacaV2Oracle _alpacaV2Oracle = IAlpacaV2Oracle(_moneyMarket.getOracle());

    uint256 _len = _underlyingTokens.length;
    _alpacaGuardStatuses = new AlpacaGuardStatus[](_len);

    for (uint256 _i; _i < _len; ) {
      _alpacaGuardStatuses[_i].underlyingToken = _underlyingTokens[_i];
      try _alpacaV2Oracle.isStable(_underlyingTokens[_i]) {
        // if no error, alpaca guard is not activated
        _alpacaGuardStatuses[_i].isGuardActivated = false;
      } catch {
        _alpacaGuardStatuses[_i].isGuardActivated = true;
      }

      unchecked {
        ++_i;
      }
    }
  }
}
