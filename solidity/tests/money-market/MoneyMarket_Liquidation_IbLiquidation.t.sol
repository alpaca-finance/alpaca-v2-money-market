// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, console } from "./MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { ILiquidationFacet } from "../../contracts/money-market/facets/LiquidationFacet.sol";
import { TripleSlopeModel6, IInterestRateModel } from "../../contracts/money-market/interest-models/TripleSlopeModel6.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

// contract
import { PancakeswapV2IbTokenLiquidationStrategy } from "../../contracts/money-market/PancakeswapV2IbTokenLiquidationStrategy.sol";

// mocks
import { MockLiquidationStrategy } from "../mocks/MockLiquidationStrategy.sol";
import { MockBadLiquidationStrategy } from "../mocks/MockBadLiquidationStrategy.sol";
import { MockInterestModel } from "../mocks/MockInterestModel.sol";
import { MockLPToken } from "../mocks/MockLPToken.sol";
import { MockRouter02 } from "../mocks/MockRouter02.sol";

struct CacheState {
  // general
  uint256 mmUnderlyingBalance;
  uint256 ibTokenTotalSupply;
  uint256 treasuryDebtTokenBalance;
  // debt
  uint256 globalDebtValue;
  uint256 debtValue;
  uint256 debtShare;
  uint256 subAccountDebtShare;
  // collat
  uint256 ibTokenCollat;
  uint256 subAccountIbTokenCollat;
}

contract MoneyMarket_Liquidation_IbLiquidationTest is MoneyMarket_BaseTest {
  MockLPToken internal wethUsdcLPToken;
  MockRouter02 internal router;
  PancakeswapV2IbTokenLiquidationStrategy _ibTokenLiquidationStrat;

  uint256 _aliceSubAccountId = 0;
  address _aliceSubAccount0 = LibMoneyMarket01.getSubAccount(ALICE, _aliceSubAccountId);
  address treasury;

  function setUp() public override {
    super.setUp();

    treasury = address(this);

    TripleSlopeModel6 tripleSlope6 = new TripleSlopeModel6();
    adminFacet.setInterestModel(address(weth), address(tripleSlope6));
    adminFacet.setInterestModel(address(btc), address(tripleSlope6));
    adminFacet.setInterestModel(address(usdc), address(tripleSlope6));

    // setup liquidationStrategy
    wethUsdcLPToken = new MockLPToken("MOCK LP", "MOCK LP", 18, address(weth), address(usdc));
    router = new MockRouter02(address(wethUsdcLPToken), address(mockOracle));
    usdc.mint(address(router), 100 ether); // prepare for swap

    _ibTokenLiquidationStrat = new PancakeswapV2IbTokenLiquidationStrategy(
      address(router),
      address(moneyMarketDiamond)
    );

    address[] memory _ibTokenLiquidationStrats = new address[](2);
    _ibTokenLiquidationStrats[0] = address(_ibTokenLiquidationStrat);

    adminFacet.setLiquidationStratsOk(_ibTokenLiquidationStrats, true);

    address[] memory _liquidationCallers = new address[](2);
    _liquidationCallers[0] = BOB;
    _liquidationCallers[1] = address(this);
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
    lendFacet.deposit(address(usdc), 100 ether);
    lendFacet.deposit(address(btc), 10 ether);
    collateralFacet.addCollateral(BOB, 0, address(btc), 10 ether);
    vm.stopPrank();

    // alice add ibWETh collat for 80 ether
    vm.startPrank(ALICE);
    lendFacet.deposit(address(weth), 80 ether);
    collateralFacet.addCollateral(ALICE, 0, address(ibWeth), 40 ether);
    vm.stopPrank();

    adminFacet.setNonCollatBorrowerOk(BOB, true);
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
  // | ---------------------------------------------- |

  function testCorrectness_WhenPartialLiquidateIbCollateral_ShouldRedeemUnderlyingToPayDebtCorrectly() external {
    // criteria
    address _ibCollatToken = address(ibWeth);
    address _underlyingToken = address(weth);
    address _debtToken = address(usdc);
    uint256 _repayAmountInput = 15 ether;

    vm.prank(ALICE);
    borrowFacet.borrow(0, _debtToken, 30 ether);
    // | After Alice borrow 30 USDC
    // | ---------------------------------------------- |
    // | State                        | AMOUNT (ether)  |
    // | ---------------------------- | --------------- |
    // | ALICE USDC Debt Share        | 30              |
    // | Global USDC Debt Share       | 30              |
    // | Global USDC Debt Value       | 30              |
    // | ---------------------------------------------- |

    vm.prank(BOB);
    borrowFacet.borrow(0, _underlyingToken, 24 ether);
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
    // USDC Debt Pending Interest = 30 * 0.00016921837224 = 0.0050765511672
    // WETH Debt Pending Interest = 24 * 0.00016921837224 = 0.00406124093376
    uint256 _pendingInterest = viewFacet.getGlobalPendingInterest(_debtToken);
    assertEq(_pendingInterest, 0.0050765511672 ether, "pending interest for _debtToken");
    uint256 _underlyingInterest = viewFacet.getGlobalPendingInterest(_underlyingToken);
    assertEq(_underlyingInterest, 0.00406124093376 ether, "pending interest for _underlyingToken");

    CacheState memory _stateBefore = _cacheState(_aliceSubAccount0, _ibCollatToken, _underlyingToken, _debtToken);

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

    liquidationFacet.liquidationCall(
      address(_ibTokenLiquidationStrat),
      ALICE,
      _aliceSubAccountId,
      _debtToken,
      _ibCollatToken,
      _repayAmountInput,
      abi.encode(0)
    );

    // | Calculation When Liquidate ALICE Position
    // | -------------------------------------------------------------------------------- |
    // | Detail                       | Amount (ether)    | Note                          |
    // | ---------------------------- | ----------------- | ----------------------------- |
    // | RepayAmount                  | 15                |                               |
    // | AliceDebtValue               | 30.0050765511672  | ALICE USDC Debt Value + interest
    // | ActualRepayAmount            | 15                | Min(AliceDebtValue, RepayAmount)
    // | LiquidationFee               | 0.15              | 1% of ActualRepayAmount
    // | -------------------------------------------------------------------------------------- |

    // | in Liquidation Strat Calculation
    // | -------------------------------------------------------------------------------------------------------------- |
    // | Detail                             | Amount (ether)        | Note                                              |
    // | ---------------------------------- | --------------------- | ------------------------------------------------- |
    // | RepayAmountToStrat                 | 15.15                 | ActualRepayAmount + Fee                           |
    // | RequireUnderlyingToSwap            | 18.9375               | 15.15 * 1 / 0.8                                   |
    // |                                    |                       | RepayAmountToStrat * USDC Price / WETH Price      |
    // | AliceIbTokenCollat (X)             | 40                    |                                                   |
    // | IB WETH Total Supply               | 80                    |                                                   |
    // | UnderlyingTotalTokenWithInterest   | 80.00406124093376     | reserve + debt - protocal + interest              |
    // | RequiredIbTokenToWithdraw (Y)      | 18.936538676924769296 | 18.9375 * 80 / 80.00406124093376                  |
    // | ActualIbTokenToWithdraw            | 18.936538676924769296 | Min(X, Y)                                         |
    // | WithdrawUnderlyingToken            | 18.937499999999999999 | 18.936538676924769296 * 80.00406124093376 / 80    |
    // | ReturnedIBToken                    | 21.063461323075230704 | 40 - 18.936538676924769296                        |
    // |                                    |                       | if X > Y then X - Y else 0                        |
    // | RepayTokenFromStrat                | 15.149999999999999999 | 18.937499999999999999 * 0.8 / 1                   |
    // |                                    |                       | WithdrawUnderlyingToken * WETH Price / USDC Price |
    // | -------------------------------------------------------------------------------------------------------------- |

    // | After Execute Strat Calculation
    // | ------------------------------------------------------------------------------------------------------------- |
    // | Detail                     | Amount (ether)        | Note                                                     |
    // | -------------------------- | --------------------- | -------------------------------------------------------- |
    // | RepaidAmount (ShareValue)  | 14.999999999999999999 | RepayTokenFromStrat - LiquidationFee                     |
    // | RepaidShare                | 14.997462153866591689 | 14.999999999999999999 * 30 / 30.0050765511672            |
    // |                            |                       | RepaidAmount * DebtShare / DebtValue + interest (USDC)   |
    // | ------------------------------------------------------------------------------------------------------------- |

    // Expectation
    uint256 _expectedRepaidAmount = 14.999999999999999999 ether;
    uint256 _expectedIbTokenToWithdraw = 18.936538676924769296 ether;
    uint256 _expectedUnderlyingWitdrawnAmount = 18.937499999999999999 ether;
    uint256 _expectedLiquidationFee = 0.15 ether;

    _assertDebt(ALICE, _aliceSubAccountId, _debtToken, _expectedRepaidAmount, _pendingInterest, _stateBefore);
    _assertIbTokenCollatAndTotalSupply(_aliceSubAccount0, _ibCollatToken, _expectedIbTokenToWithdraw, _stateBefore);
    _assertWithdrawnUnderlying(_underlyingToken, _expectedUnderlyingWitdrawnAmount, _stateBefore);
    _assertTreasuryDebtTokenFee(_debtToken, _expectedLiquidationFee, _stateBefore);
  }

  function testCorrectness_WhenLiquidateIbMoreThanDebt_ShouldLiquidateAllDebtOnThatToken() external {
    adminFacet.setLiquidationParams(10000, 9000); // allow liquidation of entire subAccount

    // criteria
    address _ibCollatToken = address(ibWeth);
    address _underlyingToken = address(weth);
    address _debtToken = address(usdc);
    uint256 _repayAmountInput = 40 ether;

    vm.prank(ALICE);
    borrowFacet.borrow(0, _debtToken, 30 ether);
    // | After Alice borrow 30 USDC
    // | ---------------------------------------------- |
    // | State                        | AMOUNT (ether)  |
    // | ---------------------------- | --------------- |
    // | ALICE USDC Debt Share        | 30              |
    // | Global USDC Debt Share       | 30              |
    // | Global USDC Debt Value       | 30              |
    // | ---------------------------------------------- |

    vm.prank(BOB);
    borrowFacet.borrow(0, _underlyingToken, 24 ether);
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
    // USDC Debt Pending Interest = 30 * 0.00016921837224 = 0.0050765511672
    // WETH Debt Pending Interest = 24 * 0.00016921837224 = 0.00406124093376
    uint256 _pendingInterest = viewFacet.getGlobalPendingInterest(_debtToken);
    assertEq(_pendingInterest, 0.0050765511672 ether, "pending interest for _debtToken");
    uint256 _underlyingInterest = viewFacet.getGlobalPendingInterest(_underlyingToken);
    assertEq(_underlyingInterest, 0.00406124093376 ether, "pending interest for _underlyingToken");

    CacheState memory _stateBefore = _cacheState(_aliceSubAccount0, _ibCollatToken, _underlyingToken, _debtToken);

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

    liquidationFacet.liquidationCall(
      address(_ibTokenLiquidationStrat),
      ALICE,
      _aliceSubAccountId,
      _debtToken,
      _ibCollatToken,
      _repayAmountInput,
      abi.encode(0)
    );

    // | Calculation When Liquidate ALICE Position
    // | -------------------------------------------------------------------------------- |
    // | Detail                       | Amount (ether)    | Note                          |
    // | ---------------------------- | ----------------- | ----------------------------- |
    // | RepayAmount                  | 40                |                               |
    // | AliceDebtValue               | 30.0050765511672  | ALICE USDC Debt Value + interest
    // | ActualRepayAmount            | 30.0050765511672  | Min(AliceDebtValue, RepayAmount)
    // | LiquidationFee               | 0.300050765511672 | 1% of ActualRepayAmount
    // | -------------------------------------------------------------------------------------- |

    // | in Liquidation Strat Calculation
    // | -------------------------------------------------------------------------------------------------------------- |
    // | Detail                             | Amount (ether)        | Note                                              |
    // | ---------------------------------- | --------------------- | ------------------------------------------------- |
    // | RepayAmountToStrat                 | 30.305127316678872    | ActualRepayAmount + Fee                           |
    // | RequireUnderlyingToSwap            | 37.88140914584859     | 30.305127316678872 * 1 / 0.8                                   |
    // |                                    |                       | RepayAmountToStrat * USDC Price / WETH Price      |
    // | AliceIbTokenCollat (X)             | 40                    |                                                   |
    // | IB WETH Total Supply               | 80                    |                                                   |
    // | UnderlyingTotalTokenWithInterest   | 80.00406124093376     | reserve + debt - protocal + interest              |
    // | RequiredIbTokenToWithdraw (Y)      | 37.879486174351076617 | 37.88140914584859 * 80 / 80.00406124093376                  |
    // | ActualIbTokenToWithdraw            | 37.879486174351076617 | Min(X, Y)                                         |
    // | WithdrawUnderlyingToken            | 37.881409145848589999 | 37.879486174351076617 * 80.00406124093376 / 80    |
    // | ReturnedIBToken                    | 2.120513825648923383  | 40 - 37.879486174351076617                        |
    // |                                    |                       | if X > Y then X - Y else 0                        |
    // | RepayTokenFromStrat                | 30.305127316678871999 | 37.881409145848589999 * 0.8 / 1                   |
    // |                                    |                       | WithdrawUnderlyingToken * WETH Price / USDC Price |
    // | -------------------------------------------------------------------------------------------------------------- |

    // | After Execute Strat Calculation
    // | ------------------------------------------------------------------------------------------------------------- |
    // | Detail                     | Amount (ether)        | Note                                                     |
    // | -------------------------- | --------------------- | -------------------------------------------------------- |
    // | RepaidAmount (ShareValue)  | 30.005076551167199999 | RepayTokenFromStrat - LiquidationFee                     |
    // | RepaidShare                | 29.999999999999999999 | 30.005076551167199999 * 30 / 30.0050765511672            |
    // |                            |                       | RepaidAmount * DebtShare / DebtValue + interest (USDC)   |
    // | ------------------------------------------------------------------------------------------------------------- |

    // Expectation
    uint256 _expectedRepaidAmount = 30.005076551167199999 ether;
    uint256 _expectedIbTokenToWithdraw = 37.879486174351076617 ether;
    uint256 _expectedUnderlyingWitdrawnAmount = 37.881409145848589999 ether;
    uint256 _expectedLiquidationFee = 0.300050765511672 ether;

    _assertDebt(ALICE, _aliceSubAccountId, _debtToken, _expectedRepaidAmount, _pendingInterest, _stateBefore);
    _assertIbTokenCollatAndTotalSupply(_aliceSubAccount0, _ibCollatToken, _expectedIbTokenToWithdraw, _stateBefore);
    _assertWithdrawnUnderlying(_underlyingToken, _expectedUnderlyingWitdrawnAmount, _stateBefore);
    _assertTreasuryDebtTokenFee(_debtToken, _expectedLiquidationFee, _stateBefore);
  }

  // function testRevert_WhenLiquidateButMMDoesNotHaveEnoughUnderlyingForLiquidation() external {
  //   vm.startPrank(ALICE);
  //   lendFacet.deposit(address(weth), 40 ether);
  //   collateralFacet.addCollateral(ALICE, 0, address(ibWeth), 40 ether);
  //   collateralFacet.removeCollateral(_aliceSubAccountId, address(weth), 40 ether);
  //   vm.stopPrank();

  //   vm.warp(1 days + 1);

  //   mockOracle.setTokenPrice(address(weth), 1 ether);
  //   mockOracle.setTokenPrice(address(usdc), 1 ether);

  //   vm.startPrank(BOB);
  //   collateralFacet.addCollateral(BOB, 0, address(usdc), 100 ether);
  //   borrowFacet.borrow(0, address(weth), 30 ether);
  //   vm.stopPrank();

  //   vm.prank(BOB);
  //   lendFacet.deposit(address(weth), 1 ether);
  //   vm.prank(moneyMarketDiamond);
  //   ibWeth.onWithdraw(BOB, BOB, 0, 1 ether);

  //   mockOracle.setTokenPrice(address(weth), 8e17);
  //   // todo: check this

  //   // should fail because 11 weth left in mm not enough to liquidate 15 usdc debt
  //   vm.expectRevert("!safeTransfer");
  //   liquidationFacet.liquidationCall(
  //     address(_ibTokenLiquidationStrat),
  //     ALICE,
  //     _aliceSubAccountId,
  //     address(usdc),
  //     address(ibWeth),
  //     15 ether,
  //     abi.encode()
  //   );
  // }

  // function testRevert_WhenLiquidateIbWhileSubAccountIsHealthy() external {
  //   // add ib as collat
  //   vm.startPrank(ALICE);
  //   lendFacet.deposit(address(weth), 40 ether);
  //   collateralFacet.addCollateral(ALICE, 0, address(ibWeth), 40 ether);
  //   collateralFacet.removeCollateral(_subAccountId, address(weth), 40 ether);
  //   vm.stopPrank();

  //   // increase shareValue of ibWeth by 2.5%
  //   // wouldn need 18.475609756097... ibWeth to redeem 18.9375 weth to repay debt
  //   vm.prank(BOB);
  //   lendFacet.deposit(address(weth), 4 ether);
  //   vm.prank(moneyMarketDiamond);
  //   ibWeth.onWithdraw(BOB, BOB, 0, 4 ether);
  //   // set price to weth from 1 to 0.8 ether USD
  //   // since ibWeth collat value increase, alice borrowing power = 44 * 0.8 * 9000 / 10000 = 31.68 ether USD
  //   mockOracle.setTokenPrice(address(weth), 8e17);
  //   mockOracle.setTokenPrice(address(usdc), 1e18);
  //   mockOracle.setTokenPrice(address(btc), 10 ether);

  //   vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Healthy.selector));
  //   liquidationFacet.liquidationCall(
  //     address(mockLiquidationStrategy),
  //     ALICE,
  //     _subAccountId,
  //     address(usdc),
  //     address(ibWeth),
  //     1 ether,
  //     abi.encode()
  //   );
  // }

  // function testRevert_WhenIbLiquidateMoreThanThreshold() external {
  //   vm.startPrank(ALICE);
  //   lendFacet.deposit(address(weth), 40 ether);
  //   collateralFacet.addCollateral(ALICE, 0, address(ibWeth), 40 ether);
  //   collateralFacet.removeCollateral(_subAccountId, address(weth), 40 ether);
  //   vm.stopPrank();

  //   address _debtToken = address(usdc);
  //   address _collatToken = address(ibWeth);
  //   uint256 _repayAmount = 30 ether;

  //   mockOracle.setTokenPrice(address(weth), 8e17);
  //   mockOracle.setTokenPrice(address(usdc), 1e18);

  //   vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_RepayAmountExceedThreshold.selector));
  //   liquidationFacet.liquidationCall(
  //     address(mockLiquidationStrategy),
  //     ALICE,
  //     _subAccountId,
  //     _debtToken,
  //     _collatToken,
  //     _repayAmount,
  //     abi.encode()
  //   );
  // }

  // function testCorrectness_WhenIbLiquidateWithDebtAndInterestOnIb_ShouldAccrueInterestAndLiquidate() external {
  //   /**
  //    * scenario
  //    *
  //    * 1. ALICE add 1.5 ibWeth as collateral, borrow 1 usdc
  //    *    - borrowing power = 1.5 * 1 * 9000 / 10000 = 1.35
  //    *    - used borrowing power = 1 * 1 * 10000 / 9000 = 1.111..
  //    *
  //    * 2. BOB add 10 usdc as collateral, borrow 0.1 weth
  //    *
  //    * 3. 1 second passed, interest accrue on weth 0.001, usdc 0.01
  //    *    - note that in mm base test had lendingFee set to 0. has to account for if not 0
  //    *
  //    * 4. weth price dropped to 0.1 usdc/weth, ALICE position is liquidatable
  //    *    - ALICE borrowing power = 1.5 * 0.1 * 9000 / 10000 = 0.135
  //    *
  //    * 5. liquidate entire position by dumping 1.5 ibWeth to 0.150075 usdc
  //    *    - ibWeth collateral = 1.5 ibWeth = 1.50075 weth = 0.150075 usdc
  //    *
  //    * 6. state after liquidation
  //    *    - collat = 0
  //    *    - liquidation fee = 1.01 * 0.01 = 0.0101 usdc
  //    *    - remaining debt value = 1.01 - (0.150075 - 0.0101) = 0.870025 usdc
  //    */
  //   address _collatToken = address(ibWeth);
  //   address _debtToken = address(usdc);

  //   MockInterestModel _interestModel = new MockInterestModel(0.01 ether);
  //   adminFacet.setInterestModel(address(weth), address(_interestModel));
  //   adminFacet.setInterestModel(address(usdc), address(_interestModel));

  //   vm.startPrank(ALICE);
  //   lendFacet.deposit(address(weth), 2 ether);
  //   collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 1.5 ether);
  //   borrowFacet.repay(ALICE, subAccount0, _debtToken, 29 ether);
  //   collateralFacet.removeCollateral(subAccount0, address(weth), 40 ether);
  //   vm.stopPrank();

  //   vm.startPrank(BOB);
  //   collateralFacet.addCollateral(BOB, subAccount0, address(usdc), 10 ether);
  //   borrowFacet.borrow(subAccount0, address(weth), 0.1 ether);
  //   vm.stopPrank();

  //   vm.warp(block.timestamp + 1);

  //   assertEq(viewFacet.getGlobalPendingInterest(address(usdc)), 0.01 ether); // from ALICE
  //   assertEq(viewFacet.getGlobalPendingInterest(address(weth)), 0.001 ether); // from BOB

  //   mockOracle.setTokenPrice(address(weth), 0.1 ether);

  //   liquidationFacet.liquidationCall(
  //     address(mockLiquidationStrategy),
  //     ALICE,
  //     _subAccountId,
  //     _debtToken,
  //     _collatToken,
  //     2 ether,
  //     abi.encode()
  //   );

  //   // ALICE is rekt
  //   assertEq(viewFacet.getOverCollatSubAccountCollatAmount(_aliceSubAccount0, _collatToken), 0);
  //   (, uint256 _debtAmount) = viewFacet.getOverCollatSubAccountDebt(ALICE, subAccount0, _debtToken);
  //   assertEq(_debtAmount, 0.870025 ether);

  //   // check mm state
  //   assertEq(viewFacet.getTotalCollat(_collatToken), 0);
  //   assertEq(viewFacet.getOverCollatDebtValue(_debtToken), 0.870025 ether);
  //   // accrue weth properly
  //   assertEq(viewFacet.getGlobalPendingInterest(address(weth)), 0);
  //   assertEq(viewFacet.getDebtLastAccrueTime(address(weth)), block.timestamp);
  //   assertEq(viewFacet.getTotalToken(address(weth)), 0.50025 ether); // 2.001 - 1.50075
  //   assertEq(viewFacet.getTotalTokenWithPendingInterest(address(weth)), 0.50025 ether); // 2.001 - 1.50075
  // }

  // TODO: case where diamond has no actual token to transfer to strat

  function _cacheState(
    address _subAccount,
    address _ibToken,
    address _underlyingToken,
    address _debtToken
  ) internal view returns (CacheState memory _state) {
    (uint256 _subAccountDebtShare, ) = viewFacet.getOverCollatSubAccountDebt(ALICE, 0, _debtToken);
    _state = CacheState({
      mmUnderlyingBalance: IERC20(_underlyingToken).balanceOf(address(moneyMarketDiamond)),
      ibTokenTotalSupply: IERC20(_ibToken).totalSupply(),
      treasuryDebtTokenBalance: MockERC20(_debtToken).balanceOf(treasury),
      globalDebtValue: viewFacet.getGlobalDebtValue(_debtToken),
      debtValue: viewFacet.getOverCollatDebtValue(_debtToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      subAccountDebtShare: _subAccountDebtShare,
      ibTokenCollat: viewFacet.getTotalCollat(_ibToken),
      subAccountIbTokenCollat: viewFacet.getOverCollatSubAccountCollatAmount(_subAccount, _ibToken)
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
    (uint256 _subAccountDebtShare, ) = viewFacet.getOverCollatSubAccountDebt(_account, _subAccountId, _debtToken);
    uint256 _debtValueWithInterest = _cache.debtValue + _pendingInterest;
    uint256 _globalValueWithInterest = _cache.globalDebtValue + _pendingInterest;
    uint256 _repaidShare = (_actualRepaidAmount * _cache.debtShare) / (_debtValueWithInterest);

    assertEq(viewFacet.getOverCollatDebtValue(_debtToken), _debtValueWithInterest - _actualRepaidAmount, "debt value");
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
    address _subAccount,
    address _ibToken,
    uint256 _withdrawnIbToken,
    CacheState memory _cache
  ) internal {
    assertEq(IERC20(_ibToken).totalSupply(), _cache.ibTokenTotalSupply - _withdrawnIbToken, "ibToken totalSupply diff");

    assertEq(viewFacet.getTotalCollat(_ibToken), _cache.ibTokenCollat - _withdrawnIbToken, "collatertal");
    assertEq(
      viewFacet.getOverCollatSubAccountCollatAmount(_subAccount, _ibToken),
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

  function _assertTreasuryDebtTokenFee(
    address _debtToken,
    uint256 _liquidationFee,
    CacheState memory _cache
  ) internal {
    assertEq(MockERC20(_debtToken).balanceOf(treasury), _cache.treasuryDebtTokenBalance + _liquidationFee, "treasury");
  }
}
