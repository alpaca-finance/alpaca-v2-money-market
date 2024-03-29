// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest, MockERC20, console } from "../MoneyMarket_BaseTest.t.sol";

// interfaces
import { ILiquidationFacet } from "../../../contracts/money-market/interfaces/ILiquidationFacet.sol";
import { TripleSlopeModel6, IInterestRateModel } from "../../../contracts/money-market/interest-models/TripleSlopeModel6.sol";
import { IMiniFL } from "../../../contracts/money-market/interfaces/IMiniFL.sol";
import { IERC20 } from "../../interfaces/IERC20.sol";

// contract
import { PancakeswapV2IbTokenLiquidationStrategy } from "../../../contracts/money-market/PancakeswapV2IbTokenLiquidationStrategy.sol";

// mocks
import { MockLiquidationStrategy } from "../../mocks/MockLiquidationStrategy.sol";
import { MockBadLiquidationStrategy } from "../../mocks/MockBadLiquidationStrategy.sol";
import { MockInterestModel } from "../../mocks/MockInterestModel.sol";
import { MockLPToken } from "../../mocks/MockLPToken.sol";
import { MockRouter02 } from "../../mocks/MockRouter02.sol";

struct CacheState {
  // general
  uint256 mmUnderlyingBalance;
  uint256 ibTokenTotalSupply;
  uint256 treasuryDebtTokenBalance;
  uint256 liquidatorDebtTokenBalance;
  // debt
  uint256 globalDebtValue;
  uint256 debtValue;
  uint256 debtShare;
  uint256 subAccountDebtShare;
  // collat
  uint256 ibTokenCollat;
  uint256 subAccountIbTokenCollat;
}

contract MoneyMarket_Liquidation_IbLiquidateTest is MoneyMarket_BaseTest {
  MockLPToken internal wethUsdcLPToken;
  MockRouter02 internal router;
  PancakeswapV2IbTokenLiquidationStrategy _ibTokenLiquidationStrat;
  IMiniFL internal _miniFL;

  uint256 _aliceSubAccountId = 0;
  address _aliceSubAccount0 = address(uint160(ALICE) ^ uint160(_aliceSubAccountId));

  function setUp() public override {
    super.setUp();

    _miniFL = IMiniFL(address(miniFL));

    TripleSlopeModel6 tripleSlope6 = new TripleSlopeModel6();
    adminFacet.setInterestModel(address(weth), address(tripleSlope6));
    adminFacet.setInterestModel(address(btc), address(tripleSlope6));
    adminFacet.setInterestModel(address(usdc), address(tripleSlope6));

    // setup liquidationStrategy
    wethUsdcLPToken = new MockLPToken("MOCK LP", "MOCK LP", 18, address(weth), address(usdc));
    router = new MockRouter02(address(wethUsdcLPToken), address(mockOracle));
    usdc.mint(address(router), normalizeEther(100 ether, usdcDecimal)); // prepare for swap

    _ibTokenLiquidationStrat = new PancakeswapV2IbTokenLiquidationStrategy(
      address(router),
      address(moneyMarketDiamond)
    );

    address[] memory _ibTokenLiquidationStrats = new address[](2);
    _ibTokenLiquidationStrats[0] = address(_ibTokenLiquidationStrat);

    adminFacet.setLiquidationStratsOk(_ibTokenLiquidationStrats, true);

    address[] memory _liquidationCallers = new address[](1);
    _liquidationCallers[0] = liquidator;
    adminFacet.setLiquidatorsOk(_liquidationCallers, true);

    address[] memory _liquidationExecutors = new address[](1);
    _liquidationExecutors[0] = address(moneyMarketDiamond);
    _ibTokenLiquidationStrat.setCallersOk(_liquidationExecutors, true);

    address[] memory _paths = new address[](2);
    _paths[0] = address(weth);
    _paths[1] = address(usdc);

    PancakeswapV2IbTokenLiquidationStrategy.SetPathParams[]
      memory _setPathsInputs = new PancakeswapV2IbTokenLiquidationStrategy.SetPathParams[](1);
    _setPathsInputs[0] = PancakeswapV2IbTokenLiquidationStrategy.SetPathParams({ path: _paths });

    _ibTokenLiquidationStrat.setPaths(_setPathsInputs);

    vm.startPrank(DEPLOYER);
    mockOracle.setTokenPrice(address(btc), 10 ether);
    vm.stopPrank();

    // bob deposit 100 usdc and 10 btc
    vm.startPrank(BOB);
    accountManager.deposit(address(usdc), normalizeEther(100 ether, usdcDecimal));
    accountManager.deposit(address(btc), 10 ether);
    accountManager.addCollateralFor(BOB, 0, address(btc), 10 ether);
    vm.stopPrank();

    // alice add ibWETh collat for 80 ether
    vm.startPrank(ALICE);

    accountManager.deposit(address(weth), 40 ether);
    accountManager.depositAndAddCollateral(0, address(weth), 40 ether);
    /*
    The following block of code has the same effect as above
    // accountManager.deposit(address(weth), 80 ether);
    // ibWeth.approve(address(accountManager), 40 ether);
    // accountManager.addCollateralFor(ALICE, 0, address(ibWeth), 40 ether);
    */
    vm.stopPrank();

    adminFacet.setNonCollatBorrowerOk(BOB, true);

    address[] memory _accountManager = new address[](1);
    _accountManager[0] = address(_ibTokenLiquidationStrat);
    adminFacet.setAccountManagersOk(_accountManager, true);
  }

  // | Before test we set state like this
  // | ---------------------------------------------- |
  // | State                        | AMOUNT (ether)  |
  // | ---------------------------- | --------------- |
  // | USDC Reserve Amount          | 100             |
  // | WETH Reserve Amount          | 80              |
  // | BTC Reserve Amount           | 10              |
  // | ALICE IB WETH Collat Amount  | 40              |
  // | IB WETH Total Supply         | 80              |
  // | IB USDC Total Supply         | 100             |
  // | ---------------------------------------------- |

  function testCorrectness_WhenLiquidateIbMoreThanDebt_ShouldLiquidateAllDebtOnThatToken() external {
    adminFacet.setLiquidationParams(10000, 11111); // allow liquidation of entire subAccount

    // criteria
    address _ibCollatToken = address(ibWeth);
    address _underlyingToken = address(weth);
    address _debtToken = address(usdc);

    vm.prank(ALICE);
    accountManager.borrow(0, _debtToken, normalizeEther(30 ether, usdcDecimal));
    // | After Alice borrow 30 USDC
    // | ---------------------------------------------- |
    // | State                        | AMOUNT (ether)  |
    // | ---------------------------- | --------------- |
    // | ALICE USDC Debt Share        | 30              |
    // | Global USDC Debt Share       | 30              |
    // | Global USDC Debt Value       | 30              |
    // | ---------------------------------------------- |

    vm.prank(BOB);
    accountManager.borrow(0, _underlyingToken, 24 ether);
    // | After BOB borrow 24 WETH
    // | ---------------------------------------------- |
    // | State                        | AMOUNT (ether)  |
    // | ---------------------------- | --------------- |
    // | BOB WETH Debt Share          | 24              |
    // | Global WETH Debt Share       | 24              |
    // | Global WETH Debt Value       | 24              |
    // | ---------------------------------------------- |

    // Time past for 1 day
    vm.warp(block.timestamp + 1 days);
    // | After Time past for 1 Day
    // | -------------------------------------------------------------------- |
    // | State                        | Interest Rate : Day | Utilization (%) |
    // | ---------------------------- | ------------------- | --------------- |
    // | USDC Debt Interate rate      | 0.00016921837224    | 30% (30 : 100)  |
    // | WETH Debt Interate rate      | 0.00016921837224    | 30% (30 : 100)  |
    // | -------------------------------------------------------------------- |

    // Pending interest formula = Borrowed Amount * Interest Rate
    // USDC Debt Pending Interest = 30 * 0.00016921837224 = 0.005076
    // WETH Debt Pending Interest = 24 * 0.00016921837224 = 0.00406124093376
    uint256 _pendingInterest = viewFacet.getGlobalPendingInterest(_debtToken);
    assertEq(_pendingInterest, normalizeEther(0.005076 ether, usdcDecimal), "pending interest for _debtToken");
    uint256 _underlyingInterest = viewFacet.getGlobalPendingInterest(_underlyingToken);
    assertEq(_underlyingInterest, 0.00406124093376 ether, "pending interest for _underlyingToken");

    CacheState memory _stateBefore = _cacheState(ALICE, subAccount0, _ibCollatToken, _underlyingToken, _debtToken);

    // Prepare before liquidation
    // Dump WETH price from 1 USD to 0.8 USD, make position unhealthy
    mockOracle.setTokenPrice(_underlyingToken, 8e17);
    mockOracle.setTokenPrice(_debtToken, 1 ether);
    // | ------------------------ |
    // | TOKEN     | Price (USD)  |
    // | ------------------------ |
    // | WETH      | 0.8          |
    // | USDC      | 1            |
    // | ------------------------ |

    uint256 _collateralAmount = viewFacet.getCollatAmountOf(ALICE, _aliceSubAccountId, _ibCollatToken);
    vm.prank(liquidator);
    liquidationFacet.liquidationCall(
      address(_ibTokenLiquidationStrat),
      ALICE,
      _aliceSubAccountId,
      _debtToken,
      _ibCollatToken,
      _collateralAmount,
      0,
      ""
    );

    // | Calculation When Liquidate ALICE Position
    // | ----------------------------------------------------------------------------------- |
    // | Detail                       | Amount (ether)    | Note                             |
    // | ---------------------------- | ----------------- | -------------------------------- |
    // | RepayAmount                  | 40                |                                  |
    // | AliceDebtValue               | 30.005076         | ALICE USDC Debt Value + interest |
    // | ActualRepayAmount            | 30.005076         | Min(AliceDebtValue, RepayAmount) |
    // | LiquidationFee               | 0.300050          | 1% of ActualRepayAmount          |
    // | ----------------------------------------------------------------------------------- |

    // | in Liquidation Strat Calculation
    // | -------------------------------------------------------------------------------------------------------------- |
    // | Detail                             | Amount (ether)        | Note                                              |
    // | ---------------------------------- | --------------------- | ------------------------------------------------- |
    // | RepayAmountToStrat                 | 30.305126             | ActualRepayAmount + Fee                           |
    // | RequireUnderlyingToSwap            | 37.8814075            | 30.305126 * 1 / 0.8                               |
    // |                                    |                       | RepayAmountToStrat * USDC Price / WETH Price      |
    // | AliceIbTokenCollat (X)             | 40                    |                                                   |
    // | IB WETH Total Supply               | 80                    |                                                   |
    // | UnderlyingTotalTokenWithInterest   | 80.00406124093376     | reserve + debt - protocal + interest              |
    // | RequiredIbTokenToWithdraw (Y)      | 37.879484528586034722 | 37.8814075 * 80 / 80.00406124093376               |
    // | ActualIbTokenToWithdraw            | 37.879484528586034722 | Min(X, Y)                                         |
    // | WithdrawUnderlyingToken            | 37.881407499999999999 | 37.879484528586034722 * 80.00406124093376 / 80    |
    // | ReturnedIBToken                    | 2.1185925000000000001 | 40 - 37.881407499999999999                        |
    // |                                    |                       | if X > Y then X - Y else 0                        |
    // | RepayTokenFromStrat                | 30.305125             | 37.881407499999999999 * 0.8 / 1                   |
    // |                                    |                       | WithdrawUnderlyingToken * WETH Price / USDC Price |
    // | -------------------------------------------------------------------------------------------------------------- |

    // | After Execute Strat Calculation
    // | ----------------------------------------------------------------------------------------------------------- |
    // | Detail                     | Amount (ether)        | Note                                                   |
    // | -------------------------- | --------------------- | ------------------------------------------------------ |
    // | ActualLiquidationFee       | 0.300049              | 30.305125 / 30.305126 * 0.300050                       |
    // | RepaidAmount (ShareValue)  | 30.005076             | RepayTokenFromStrat - ActualLiquidationFee             |
    // | RepaidShare                | 30                    | 30.005076 * 30 / 30.005076                             |
    // |                            |                       | RepaidAmount * DebtShare / DebtValue + interest (USDC) |
    // | ----------------------------------------------------------------------------------------------------------- |

    // Expectation
    uint256 _expectedRepaidAmount = normalizeEther(30.005076 ether, usdcDecimal);
    uint256 _expectedIbTokenToWithdraw = 37.879484528586034722 ether;
    uint256 _expectedUnderlyingWitdrawnAmount = 37.881407499999999999 ether;
    uint256 _expectedLiquidationFeeToTrasury = normalizeEther(0.300049 ether, usdcDecimal);

    _assertDebt(ALICE, _aliceSubAccountId, _debtToken, _expectedRepaidAmount, _pendingInterest, _stateBefore);
    _assertIbTokenCollatAndTotalSupply(ALICE, subAccount0, _ibCollatToken, _expectedIbTokenToWithdraw, _stateBefore);
    _assertWithdrawnUnderlying(_underlyingToken, _expectedUnderlyingWitdrawnAmount, _stateBefore);
    _assertTreasuryFee(_debtToken, _expectedLiquidationFeeToTrasury, _stateBefore);

    // check staking ib token in MiniFL
    uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(_ibCollatToken);
    assertEq(_miniFL.getUserTotalAmountOf(_poolId, ALICE), 40 ether - _expectedIbTokenToWithdraw);
  }

  function testCorrectness_WhenPartialLiquidateIbt_ShouldPartialLiquidateDebtOnThatToken() external {
    adminFacet.setLiquidationParams(10000, 11111); // allow liquidation of entire subAccount

    // criteria
    address _ibCollatToken = address(ibWeth);
    address _underlyingToken = address(weth);
    address _debtToken = address(usdc);

    vm.prank(ALICE);
    accountManager.borrow(0, _debtToken, normalizeEther(30 ether, usdcDecimal));
    // | After Alice borrow 30 USDC
    // | ---------------------------------------------- |
    // | State                        | AMOUNT (ether)  |
    // | ---------------------------- | --------------- |
    // | ALICE USDC Debt Share        | 30              |
    // | Global USDC Debt Share       | 30              |
    // | Global USDC Debt Value       | 30              |
    // | ---------------------------------------------- |

    vm.prank(BOB);
    accountManager.borrow(0, _underlyingToken, 24 ether);
    // | After BOB borrow 24 WETH
    // | ---------------------------------------------- |
    // | State                        | AMOUNT (ether)  |
    // | ---------------------------- | --------------- |
    // | BOB WETH Debt Share          | 24              |
    // | Global WETH Debt Share       | 24              |
    // | Global WETH Debt Value       | 24              |
    // | ---------------------------------------------- |

    // Time past for 1 day
    vm.warp(block.timestamp + 1 days);
    // | After Time past for 1 Day
    // | -------------------------------------------------------------------- |
    // | State                        | Interest Rate : Day | Utilization (%) |
    // | ---------------------------- | ------------------- | --------------- |
    // | USDC Debt Interate rate      | 0.00016921837224    | 30% (30 : 100)  |
    // | WETH Debt Interate rate      | 0.00016921837224    | 30% (30 : 100)  |
    // | -------------------------------------------------------------------- |

    // Pending interest formula = Borrowed Amount * Interest Rate
    // USDC Debt Pending Interest = 30 * 0.00016921837224 = 0.005076
    // WETH Debt Pending Interest = 24 * 0.00016921837224 = 0.00406124093376
    uint256 _pendingInterest = viewFacet.getGlobalPendingInterest(_debtToken);
    assertEq(_pendingInterest, normalizeEther(0.005076 ether, usdcDecimal), "pending interest for _debtToken");
    uint256 _underlyingInterest = viewFacet.getGlobalPendingInterest(_underlyingToken);
    assertEq(_underlyingInterest, 0.00406124093376 ether, "pending interest for _underlyingToken");

    CacheState memory _stateBefore = _cacheState(ALICE, subAccount0, _ibCollatToken, _underlyingToken, _debtToken);

    // Prepare before liquidation
    // Dump WETH price from 1 USD to 0.8 USD, make position unhealthy
    mockOracle.setTokenPrice(_underlyingToken, 8e17);
    mockOracle.setTokenPrice(_debtToken, 1 ether);
    // | ------------------------ |
    // | TOKEN     | Price (USD)  |
    // | ------------------------ |
    // | WETH      | 0.8          |
    // | USDC      | 1            |
    // | ------------------------ |

    // trying to liquidate half of collateral
    uint256 _collateralAmount = viewFacet.getCollatAmountOf(ALICE, _aliceSubAccountId, _ibCollatToken);
    vm.prank(liquidator);
    liquidationFacet.liquidationCall(
      address(_ibTokenLiquidationStrat),
      ALICE,
      _aliceSubAccountId,
      _debtToken,
      _ibCollatToken,
      _collateralAmount / 2,
      0,
      ""
    );

    // Expectation
    uint256 _expectedIbTokenToWithdraw = 20 ether;
    uint256 _expectedUnderlyingWitdrawnAmount = 20.001015310233440000 ether;
    // repaying 16.0008122481868
    // actual repaid  = 16.0008122481868 * 100 / 101 = 15.8423883645
    uint256 _expectedRepaidAmount = normalizeEther(15.842389 ether, usdcDecimal);
    uint256 _expectedLiquidationFeeToTrasury = normalizeEther(0.15842389 ether, usdcDecimal);

    _assertDebt(ALICE, _aliceSubAccountId, _debtToken, _expectedRepaidAmount, _pendingInterest, _stateBefore);
    _assertIbTokenCollatAndTotalSupply(ALICE, subAccount0, _ibCollatToken, _expectedIbTokenToWithdraw, _stateBefore);
    _assertWithdrawnUnderlying(_underlyingToken, _expectedUnderlyingWitdrawnAmount, _stateBefore);
    _assertTreasuryFee(_debtToken, _expectedLiquidationFeeToTrasury, _stateBefore);

    // check staking ib token in MiniFL
    uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(_ibCollatToken);
    assertEq(_miniFL.getUserTotalAmountOf(_poolId, ALICE), 40 ether - _expectedIbTokenToWithdraw);
  }

  function testCorrectness_WhenLiquidateIbTokenCollatIsLessThanRequire_DebtShouldRepayAndCollatShouldBeGone() external {
    adminFacet.setLiquidationParams(10000, 11111); // allow liquidation of entire subAccount

    // criteria
    address _ibCollatToken = address(ibWeth);
    address _underlyingToken = address(weth);
    address _debtToken = address(usdc);

    vm.startPrank(ALICE);
    accountManager.addCollateralFor(ALICE, _aliceSubAccountId, _underlyingToken, 30 ether);
    accountManager.removeCollateral(_aliceSubAccountId, _ibCollatToken, 30 ether);
    vm.stopPrank();
    // | After Alice adjust Collateral state will changed a bit
    // | ---------------------------------------------- |
    // | State                        | AMOUNT (ether)  |
    // | ---------------------------- | --------------- |
    // | ALICE IB WETH Collat Amount  | 10              |
    // | ALICE WETH Collat Amount     | 30              |
    // | ---------------------------------------------- |

    vm.prank(ALICE);
    accountManager.borrow(0, _debtToken, normalizeEther(30 ether, usdcDecimal));
    // | After Alice borrow 30 USDC
    // | ---------------------------------------------- |
    // | State                        | AMOUNT (ether)  |
    // | ---------------------------- | --------------- |
    // | ALICE USDC Debt Share        | 30              |
    // | Global USDC Debt Share       | 30              |
    // | Global USDC Debt Value       | 30              |
    // | ---------------------------------------------- |

    vm.prank(BOB);
    accountManager.borrow(0, _underlyingToken, 24 ether);
    // | After BOB borrow 24 WETH
    // | ---------------------------------------------- |
    // | State                        | AMOUNT (ether)  |
    // | ---------------------------- | --------------- |
    // | BOB WETH Debt Share          | 24              |
    // | Global WETH Debt Share       | 24              |
    // | Global WETH Debt Value       | 24              |
    // | ---------------------------------------------- |

    // Time past for 1 day
    vm.warp(block.timestamp + 1 days);
    // | After Time past for 1 Day
    // | -------------------------------------------------------------------- |
    // | State                        | Interest Rate : Day | Utilization (%) |
    // | ---------------------------- | ------------------- | --------------- |
    // | USDC Debt Interate rate      | 0.00016921837224    | 30% (30 : 100)  |
    // | WETH Debt Interate rate      | 0.00016921837224    | 30% (30 : 100)  |
    // | -------------------------------------------------------------------- |

    // Pending interest formula = Borrowed Amount * Interest Rate
    // USDC Debt Pending Interest = 30 * 0.00016921837224 = 0.005076
    // WETH Debt Pending Interest = 24 * 0.00016921837224 = 0.00406124093376
    uint256 _pendingInterest = viewFacet.getGlobalPendingInterest(_debtToken);
    assertEq(_pendingInterest, normalizeEther(0.005076 ether, usdcDecimal), "pending interest for _debtToken");
    uint256 _underlyingInterest = viewFacet.getGlobalPendingInterest(_underlyingToken);
    assertEq(_underlyingInterest, 0.00406124093376 ether, "pending interest for _underlyingToken");

    CacheState memory _stateBefore = _cacheState(ALICE, subAccount0, _ibCollatToken, _underlyingToken, _debtToken);

    // Prepare before liquidation
    // Dump WETH price from 1 USD to 0.8 USD, make position unhealthy
    mockOracle.setTokenPrice(_underlyingToken, 8e17);
    mockOracle.setTokenPrice(_debtToken, 1 ether);
    // | ------------------------ |
    // | TOKEN     | Price (USD)  |
    // | ------------------------ |
    // | WETH      | 0.8          |
    // | USDC      | 1            |
    // | ------------------------ |
    uint256 _collateralAmount = viewFacet.getCollatAmountOf(ALICE, _aliceSubAccountId, _ibCollatToken);

    vm.prank(liquidator);
    liquidationFacet.liquidationCall(
      address(_ibTokenLiquidationStrat),
      ALICE,
      _aliceSubAccountId,
      _debtToken,
      _ibCollatToken,
      _collateralAmount,
      0,
      ""
    );

    // | Calculation When Liquidate ALICE Position
    // | ------------------------------------------------------------------------------------ |
    // | Detail                       | Amount (ether)    | Note                              |
    // | ---------------------------- | ----------------- | --------------------------------- |
    // | RepayAmount                  | 40                |                                   |
    // | AliceDebtValue               | 30.005076         | ALICE USDC Debt Value + interest  |
    // | ActualRepayAmount            | 30.005076         | Min(AliceDebtValue, RepayAmount)  |
    // | LiquidationFee               | 0.30005           | 1% of ActualRepayAmount           |
    // | ------------------------------------------------------------------------------------ |

    // | in Liquidation Strat Calculation
    // | -------------------------------------------------------------------------------------------------------------- |
    // | Detail                             | Amount (ether)        | Note                                              |
    // | ---------------------------------- | --------------------- | ------------------------------------------------- |
    // | RepayAmountToStrat                 | 30.305126             | ActualRepayAmount + Fee                           |
    // | RequireUnderlyingToSwap            | 37.8814075            | 30.305126 * 1 / 0.8                               |
    // |                                    |                       | RepayAmountToStrat * USDC Price / WETH Price      |
    // | AliceIbTokenCollat (X)             | 10                    |                                                   |
    // | IB WETH Total Supply               | 80                    |                                                   |
    // | UnderlyingTotalTokenWithInterest   | 80.00406124093376     | reserve + debt - protocal + interest              |
    // | RequiredIbTokenToWithdraw (Y)      | 37.879484528586034722 | 37.8814075 * 80 / 80.00406124093376               |
    // | ActualIbTokenToWithdraw            | 10                    | Min(X, Y)                                         |
    // | WithdrawUnderlyingToken            | 10.00050765511672     | 10 * 80.00406124093376 / 80                       |
    // | ReturnedIBToken                    | 0                     | 10 - 10                                           |
    // |                                    |                       | if X > Y then X - Y else 0                        |
    // | RepayTokenFromStrat                | 8.000406              | 10.00050765511672 * 0.8 / 1                       |
    // |                                    |                       | WithdrawUnderlyingToken * WETH Price / USDC Price |
    // | -------------------------------------------------------------------------------------------------------------- |

    // | After Execute Strat Calculation
    // | ---------------------------------------------------------------------------------------------------------------- |
    // | Detail                     | Amount (ether)        | Note                                                        |
    // | -------------------------- | --------------------- | ----------------------------------------------------------- |
    // | ActualLiquidationFee       | 0.079211              | 8.000406 / 30.305127 * 0.300050                             |
    // | RepaidAmount (ShareValue)  | 7.921195              | RepayTokenFromStrat - ActualLiquidationFee                  |
    // | RepaidShare                | 7.919854              | 7.921195 * 30 / 30.005076                                   |
    // |                            |                       | RepaidAmount * DebtShare / DebtValue + interest (USDC)      |
    // | ---------------------------------------------------------------------------------------------------------------- |

    // Expectation
    uint256 _expectedRepaidAmount = normalizeEther(7.921195 ether, usdcDecimal);
    uint256 _expectedIbTokenToWithdraw = 10 ether;
    uint256 _expectedUnderlyingWitdrawnAmount = 10.00050765511672 ether;
    uint256 _expectedFeeToTreasury = normalizeEther(0.079211 ether, usdcDecimal);

    _assertDebt(ALICE, _aliceSubAccountId, _debtToken, _expectedRepaidAmount, _pendingInterest, _stateBefore);
    _assertIbTokenCollatAndTotalSupply(ALICE, subAccount0, _ibCollatToken, _expectedIbTokenToWithdraw, _stateBefore);
    _assertWithdrawnUnderlying(_underlyingToken, _expectedUnderlyingWitdrawnAmount, _stateBefore);
    _assertTreasuryFee(_debtToken, _expectedFeeToTreasury, _stateBefore);

    // check staking ib token in MiniFL
    uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(_ibCollatToken);
    assertEq(IMiniFL(address(miniFL)).getUserTotalAmountOf(_poolId, ALICE), 0);
  }

  function testRevert_WhenPartialLiquidateIbCollateral_RepayTokenAndUnderlyingAreSame() external {
    // criteria
    address _ibCollatToken = address(ibUsdc);
    address _debtToken = address(usdc);

    vm.startPrank(ALICE);

    accountManager.depositAndAddCollateral(0, address(usdc), normalizeEther(1 ether, usdcDecimal));

    accountManager.borrow(0, _debtToken, normalizeEther(30 ether, usdcDecimal));
    vm.stopPrank();

    // Time past for 1 day
    vm.warp(block.timestamp + 1 days);

    // Prepare before liquidation
    // Dump WETH price from 1 USD to 0.8 USD, make position unhealthy
    mockOracle.setTokenPrice(address(weth), 8e17);
    mockOracle.setTokenPrice(_debtToken, 1 ether);

    uint256 _collateralAmount = viewFacet.getCollatAmountOf(ALICE, _aliceSubAccountId, _ibCollatToken);

    vm.prank(liquidator);
    vm.expectRevert(
      abi.encodeWithSelector(
        PancakeswapV2IbTokenLiquidationStrategy
          .PancakeswapV2IbTokenLiquidationStrategy_RepayTokenIsSameWithUnderlyingToken
          .selector
      )
    );
    liquidationFacet.liquidationCall(
      address(_ibTokenLiquidationStrat),
      ALICE,
      _aliceSubAccountId,
      _debtToken,
      _ibCollatToken,
      _collateralAmount,
      0,
      ""
    );
  }

  function testRevert_WhenLiquidateIbWhileSubAccountIsHealthy() external {
    vm.prank(ALICE);
    accountManager.borrow(0, address(usdc), normalizeEther(30 ether, usdcDecimal));

    // increase shareValue of ibWeth by 2.5%
    // wouldn need 18.475609756097... ibWeth to redeem 18.9375 weth to repay debt
    vm.prank(BOB);
    accountManager.deposit(address(weth), 4 ether);
    vm.prank(moneyMarketDiamond);
    ibWeth.onWithdraw(BOB, BOB, 0, 4 ether);
    // set price to weth from 1 to 0.8 ether USD
    // since ibWeth collat value increase, alice borrowing power = 44 * 0.8 * 9000 / 10000 = 31.68 ether USD
    mockOracle.setTokenPrice(address(weth), 8e17);
    mockOracle.setTokenPrice(address(usdc), 1e18);
    mockOracle.setTokenPrice(address(btc), 10 ether);

    uint256 _collateralAmount = viewFacet.getCollatAmountOf(ALICE, _aliceSubAccountId, address(ibWeth));

    vm.prank(liquidator);
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Healthy.selector));
    liquidationFacet.liquidationCall(
      address(_ibTokenLiquidationStrat),
      ALICE,
      _aliceSubAccountId,
      address(usdc),
      address(ibWeth),
      _collateralAmount,
      0,
      ""
    );
  }

  function testRevert_WhenIbLiquidateMoreThanThreshold() external {
    vm.prank(ALICE);
    accountManager.borrow(0, address(usdc), normalizeEther(30 ether, usdcDecimal));

    mockOracle.setTokenPrice(address(weth), 8e17);
    mockOracle.setTokenPrice(address(usdc), 1e18);

    uint256 _collateralAmount = viewFacet.getCollatAmountOf(ALICE, _aliceSubAccountId, address(ibWeth));
    vm.prank(liquidator);
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_RepayAmountExceedThreshold.selector));
    liquidationFacet.liquidationCall(
      address(_ibTokenLiquidationStrat),
      ALICE,
      _aliceSubAccountId,
      address(usdc),
      address(ibWeth),
      _collateralAmount,
      0,
      ""
    );
  }

  function _cacheState(
    address _account,
    uint256 _subAccountId,
    address _ibToken,
    address _underlyingToken,
    address _debtToken
  ) internal view returns (CacheState memory _state) {
    (uint256 _subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, _debtToken);
    _state = CacheState({
      mmUnderlyingBalance: IERC20(_underlyingToken).balanceOf(address(moneyMarketDiamond)),
      ibTokenTotalSupply: IERC20(_ibToken).totalSupply(),
      treasuryDebtTokenBalance: MockERC20(_debtToken).balanceOf(liquidationTreasury),
      liquidatorDebtTokenBalance: MockERC20(_debtToken).balanceOf(liquidator),
      globalDebtValue: viewFacet.getGlobalDebtValue(_debtToken),
      debtValue: viewFacet.getOverCollatTokenDebtValue(_debtToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      subAccountDebtShare: _subAccountDebtShare,
      ibTokenCollat: viewFacet.getTotalCollat(_ibToken),
      subAccountIbTokenCollat: viewFacet.getCollatAmountOf(_account, _subAccountId, _ibToken)
    });
  }

  function _assertDebt(
    address _account,
    uint256 _subAccountId,
    address _debtToken,
    uint256 _actualRepaidAmount,
    uint256 _pendingInterest,
    CacheState memory _cache
  ) internal {
    (uint256 _subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(_account, _subAccountId, _debtToken);
    uint256 _debtValueWithInterest = _cache.debtValue + _pendingInterest;
    uint256 _globalValueWithInterest = _cache.globalDebtValue + _pendingInterest;
    uint256 _repaidShare = (_actualRepaidAmount * _cache.debtShare) / (_debtValueWithInterest);

    assertEq(
      viewFacet.getOverCollatTokenDebtValue(_debtToken),
      _debtValueWithInterest - _actualRepaidAmount,
      "debt value"
    );
    assertEq(viewFacet.getOverCollatTokenDebtShares(_debtToken), _cache.debtShare - _repaidShare, "debt share");
    assertEq(_subAccountDebtShare, _cache.subAccountDebtShare - _repaidShare, "sub account debt share");

    // globalDebt should equal to debtValue since there is only 1 position
    assertEq(
      viewFacet.getGlobalDebtValue(_debtToken),
      _globalValueWithInterest - _actualRepaidAmount,
      "global debt value"
    );
  }

  function _assertIbTokenCollatAndTotalSupply(
    address _account,
    uint256 _subAccountId,
    address _ibToken,
    uint256 _withdrawnIbToken,
    CacheState memory _cache
  ) internal {
    assertEq(IERC20(_ibToken).totalSupply(), _cache.ibTokenTotalSupply - _withdrawnIbToken, "ibToken totalSupply diff");

    assertEq(viewFacet.getTotalCollat(_ibToken), _cache.ibTokenCollat - _withdrawnIbToken, "collatertal");
    assertEq(
      viewFacet.getCollatAmountOf(_account, _subAccountId, _ibToken),
      _cache.subAccountIbTokenCollat - _withdrawnIbToken,
      "sub account collatertal"
    );
  }

  function _assertWithdrawnUnderlying(
    address _underlyingToken,
    uint256 _withdrawnAmount,
    CacheState memory _cache
  ) internal {
    assertEq(
      IERC20(_underlyingToken).balanceOf(address(moneyMarketDiamond)),
      _cache.mmUnderlyingBalance - _withdrawnAmount,
      "MM underlying balance should not be affected"
    );
  }

  function _assertTreasuryFee(address _debtToken, uint256 _feeToTreasury, CacheState memory _cache) internal {
    assertEq(
      MockERC20(_debtToken).balanceOf(liquidationTreasury),
      _cache.treasuryDebtTokenBalance + _feeToTreasury,
      "treasury"
    );
  }
}
