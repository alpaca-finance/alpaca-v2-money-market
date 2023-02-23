// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, DebtToken, console } from "../MoneyMarket_BaseTest.t.sol";
import "solidity/tests/utils/StdUtils.sol";
import "solidity/tests/utils/StdAssertions.sol";
import "solidity/tests/utils/StdCheats.sol";

// libs
import { LibMoneyMarket01 } from "../../../contracts/money-market/libraries/LibMoneyMarket01.sol";
import { LibShareUtil } from "../../../contracts/money-market/libraries/LibShareUtil.sol";

// interfaces
import { IAdminFacet } from "../../../contracts/money-market/facets/AdminFacet.sol";
import { ILiquidationFacet } from "../../../contracts/money-market/facets/LiquidationFacet.sol";

import { IMiniFL } from "../../../contracts/money-market/interfaces/IMiniFL.sol";
import { IERC20 } from "solidity/contracts/money-market/interfaces/IERC20.sol";

// contracts
import { FixedFeeModel } from "../../../contracts/money-market/fee-models/FixedFeeModel.sol";

// mocks
import { MockInterestModel } from "solidity/tests/mocks/MockInterestModel.sol";

contract MoneyMarket_Liquidation_NewRepurchaseTest is MoneyMarket_BaseTest, StdUtils, StdAssertions, StdCheats {
  IMiniFL internal _miniFL;

  function setUp() public override {
    super.setUp();

    _miniFL = IMiniFL(address(miniFL));

    /**
     * setup
     *  - initial prices: 1 weth = 1 usd, 1 usdc = 1 usd
     *  - all token have collatFactor 9000, borrowFactor 9000
     *  - 10% fee, 1% reward
     *  - allow to repurchase up to 100% of position
     *  - fixed 0.01% (1 bps) interest per block for all token
     */
    mockOracle.setTokenPrice(address(weth), 1 ether);
    mockOracle.setTokenPrice(address(usdc), 1 ether);
    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](2);
    _inputs[0] = IAdminFacet.TokenConfigInput({
      token: address(weth),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxCollateral: 1e40,
      maxBorrow: 1e40
    });
    _inputs[1] = IAdminFacet.TokenConfigInput({
      token: address(usdc),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxCollateral: 1e40,
      maxBorrow: 1e40
    });
    adminFacet.setTokenConfigs(_inputs);
    adminFacet.setFees(0, 1000, 0, 0);
    adminFacet.setLiquidationParams(10000, 10000);
    FixedFeeModel fixedFeeModel = new FixedFeeModel();
    adminFacet.setRepurchaseRewardModel(fixedFeeModel);
    // 1e16 = 0.01% interest per block
    MockInterestModel interestModel = new MockInterestModel(1e16);
    adminFacet.setInterestModel(address(usdc), address(interestModel));
    adminFacet.setInterestModel(address(weth), address(interestModel));

    // seed money market
    vm.startPrank(BOB);
    accountManager.deposit(address(usdc), normalizeEther(1000 ether, usdcDecimal));
    accountManager.deposit(address(btc), normalizeEther(100 ether, btcDecimal));
    accountManager.deposit(address(weth), normalizeEther(100 ether, wethDecimal));
    vm.stopPrank();
  }

  modifier makeAliceUnderwater() {
    /**
     * setup ALICE initial state
     *  - collateral 2.4 usdc (max collateral that would still allow position
     *                         to be liquidated when weth = 2 usd is 2.469... usdc)
     *  - debt 1 weth
     */
    uint256 _initialCollateralAmount = 2.4 ether;
    uint256 _initialDebtAmount = 1 ether;
    vm.startPrank(ALICE);
    accountManager.addCollateralFor(
      ALICE,
      subAccount0,
      address(usdc),
      normalizeEther(_initialCollateralAmount, usdcDecimal)
    );
    accountManager.borrow(subAccount0, address(weth), _initialDebtAmount);
    vm.stopPrank();

    /**
     * weth price change 1 usd -> 2 usd
     * ALICE position become repurchasable
     *  - totalBorrowingPower = sum(collatAmount * price * collatFactor)
     *                        = 2.4 * 1 * 9000 = 21600
     *  - usedBorrowingPower = sum(debtAmount * price / borrowFactor)
     *                       = 1 * 2 / 0.9 = 22222
     */
    mockOracle.setTokenPrice(address(weth), 2 ether);

    _;
  }

  struct TestRepurchaseContext {
    address borrower;
    address repurchaser;
    address collatToken;
    address debtToken;
    uint256 desiredRepayAmount;
    uint256 repurchaseFeeBps;
    uint256 collatTokenPrice;
    uint256 debtTokenPriceDuringRepurchase;
    uint256 borrowerPendingInterest;
    TestRepurchaseStateBefore stateBefore;
  }

  struct TestRepurchaseStateBefore {
    uint256 borrowerDebtAmount;
    uint256 borrowerDebtShares;
    uint256 borrowerCollateralAmount;
    uint256 repurchaserDebtTokenBalance;
    uint256 repurchaserCollatTokenBalance;
    uint256 treasuryDebtTokenBalance;
    uint256 debtTokenReserve;
    uint256 debtTokenOverCollatDebtShares;
    uint256 debtTokenOverCollatDebtAmount;
    uint256 debtTokenGlobalDebtValue;
  }

  /// @dev this function will test
  ///         - repay amount and fee calculation
  ///         - collateral amount sold calculation
  ///         - borrower collateral and debt accounting changes
  ///         - repurchaser collateral and debt token balance changes
  ///         - money market debt, reserve accounting changes
  ///         - treasury debtToken balance changes
  ///         - miniFL debtToken staking balance changes
  /// @dev must handle pending interest manually with `ctx.borrowerPendingInterest`
  ///      since some view facet function doesn't include pending interest
  function _testRepurchase(TestRepurchaseContext memory ctx) internal {
    /**
     * calculation
     *  - maxAmountRepurchaseable = currentDebt * (1 + feePct)
     *  - fee = repayAmountWithFee - repayAmountWithoutFee
     *  - repayTokenPriceWithPremium = repayTokenPrice * (1 + rewardPct)
     *  - collatAmountOut = repayAmountWithFee * repayTokenPriceWithPremium / collatTokenPrice
     *
     * case 1: desiredRepayAmount > maxAmountRepurchaseable
     *  - repayAmountWithFee = maxAmountRepurchaseable
     *  - repayAmountWithoutFee = currentDebt
     *
     * case 2: desiredRepayAmount <= maxAmountRepurchaseable
     *  - repayAmountWithFee = desiredRepayAmount
     *  - repayAmountWithoutFee = desiredRepayAmount / (1 + feePct)
     */
    ctx.stateBefore.repurchaserDebtTokenBalance = IERC20(ctx.debtToken).balanceOf(ctx.repurchaser);
    ctx.stateBefore.repurchaserCollatTokenBalance = IERC20(ctx.collatToken).balanceOf(ctx.repurchaser);
    ctx.stateBefore.treasuryDebtTokenBalance = IERC20(ctx.debtToken).balanceOf(liquidationTreasury);
    ctx.stateBefore.debtTokenReserve = viewFacet.getFloatingBalance(ctx.debtToken);
    ctx.stateBefore.debtTokenGlobalDebtValue = viewFacet.getGlobalDebtValueWithPendingInterest(ctx.debtToken);
    ctx.stateBefore.borrowerCollateralAmount = viewFacet.getCollatAmountOf(ctx.borrower, subAccount0, ctx.collatToken);
    (ctx.stateBefore.borrowerDebtShares, ctx.stateBefore.borrowerDebtAmount) = viewFacet
      .getOverCollatDebtShareAndAmountOf(ctx.borrower, subAccount0, ctx.debtToken);
    // workaround for debtAmount and debtShares
    // since `getOverCollatDebtShareAndAmountOf` doesn't include pending interest of the position
    // so we have to calculated for value included interest manually
    ctx.stateBefore.borrowerDebtAmount += ctx.borrowerPendingInterest;
    ctx.stateBefore.debtTokenOverCollatDebtShares = viewFacet.getOverCollatTokenDebtShares(ctx.debtToken);
    ctx.stateBefore.debtTokenOverCollatDebtAmount =
      viewFacet.getOverCollatTokenDebtValue(ctx.debtToken) +
      ctx.borrowerPendingInterest;

    ///////////////////////////////////
    // ghost variables calculation
    ///////////////////////////////////
    uint256 _repayAmountWithFee;
    uint256 _repayAmountWithoutFee;
    {
      uint256 _maxAmountRepurchasable = (ctx.stateBefore.borrowerDebtAmount * (10000 + ctx.repurchaseFeeBps)) / 10000;
      // case 1
      if (ctx.desiredRepayAmount > _maxAmountRepurchasable) {
        _repayAmountWithFee = _maxAmountRepurchasable;
        _repayAmountWithoutFee = ctx.stateBefore.borrowerDebtAmount;
      } else {
        // case 2
        _repayAmountWithFee = ctx.desiredRepayAmount;
        _repayAmountWithoutFee = (ctx.desiredRepayAmount * 10000) / (10000 + (ctx.repurchaseFeeBps));
      }
    }
    uint256 _repurchaseFee = _repayAmountWithFee - _repayAmountWithoutFee;
    // constant 1% premium
    uint256 _repayTokenPriceWithPremium = (ctx.debtTokenPriceDuringRepurchase * (10000 + 100)) / 10000;
    uint256 _collatSold = (_repayAmountWithFee * _repayTokenPriceWithPremium) / ctx.collatTokenPrice;

    ///////////////////////////////////
    // repurchase
    ///////////////////////////////////
    vm.prank(ctx.repurchaser);
    liquidationFacet.repurchase(ctx.borrower, subAccount0, ctx.debtToken, ctx.collatToken, ctx.desiredRepayAmount);

    ///////////////////////////////////
    // assertions
    ///////////////////////////////////
    /**
     * borrower final state
     *  - collateral = initial - collatSold
     *  - debt = initial - repayAmountWithoutFee
     */
    {
      assertEq(
        viewFacet.getCollatAmountOf(ctx.borrower, subAccount0, ctx.collatToken),
        ctx.stateBefore.borrowerCollateralAmount - normalizeEther(_collatSold, IERC20(ctx.collatToken).decimals()),
        "borrower remaining collat"
      );
      (uint256 _debtSharesAfter, uint256 _debtAmountAfter) = viewFacet.getOverCollatDebtShareAndAmountOf(
        ctx.borrower,
        subAccount0,
        ctx.debtToken
      );
      assertEq(
        _debtAmountAfter,
        ctx.stateBefore.borrowerDebtAmount - normalizeEther(_repayAmountWithoutFee, IERC20(ctx.debtToken).decimals()),
        "borrower remaining debt amount"
      );
      assertEq(
        _debtSharesAfter,
        ctx.stateBefore.borrowerDebtShares -
          normalizeEther(
            LibShareUtil.valueToShare(
              _repayAmountWithoutFee,
              ctx.stateBefore.debtTokenOverCollatDebtShares,
              ctx.stateBefore.debtTokenOverCollatDebtAmount
            ),
            IERC20(ctx.debtToken).decimals()
          ),
        "borrower remaining debt shares"
      );
    }

    /**
     * repurchaser final state
     *  - collateral = initial + payout
     *  - debt = initial - paid
     */
    if (ctx.collatToken == ctx.debtToken) {
      assertEq(
        IERC20(ctx.collatToken).balanceOf(ctx.repurchaser),
        ctx.stateBefore.repurchaserCollatTokenBalance +
          normalizeEther(_collatSold, IERC20(ctx.collatToken).decimals()) -
          normalizeEther(_repayAmountWithFee, IERC20(ctx.debtToken).decimals()),
        "collatToken == debtToken: repurchaser collatToken received"
      );
    } else {
      assertEq(
        IERC20(ctx.collatToken).balanceOf(ctx.repurchaser),
        ctx.stateBefore.repurchaserCollatTokenBalance + normalizeEther(_collatSold, IERC20(ctx.collatToken).decimals()),
        "repurchaser collatToken received"
      );
      assertEq(
        IERC20(ctx.debtToken).balanceOf(ctx.repurchaser),
        ctx.stateBefore.repurchaserDebtTokenBalance -
          normalizeEther(_repayAmountWithFee, IERC20(ctx.debtToken).decimals()),
        "repurchaser debtToken paid"
      );
    }

    /**
     * money market final state
     *  - debtToken overCollatDebtValue -= _repayAmountWithoutFee
     *  - debtToken globalDebt -= _repayAmountWithoutFee
     *  - debtToken reserve += _repayAmountWithoutFee
     */
    assertEq(
      viewFacet.getOverCollatTokenDebtValue(ctx.debtToken),
      ctx.stateBefore.debtTokenOverCollatDebtAmount -
        normalizeEther(_repayAmountWithoutFee, IERC20(ctx.debtToken).decimals()),
      "money market debtToken overCollatDebtValue"
    );
    assertEq(
      viewFacet.getOverCollatTokenDebtShares(ctx.debtToken),
      ctx.stateBefore.debtTokenOverCollatDebtShares -
        normalizeEther(
          LibShareUtil.valueToShare(
            _repayAmountWithoutFee,
            ctx.stateBefore.debtTokenOverCollatDebtShares,
            ctx.stateBefore.debtTokenOverCollatDebtAmount
          ),
          IERC20(ctx.debtToken).decimals()
        ),
      "money market debtToken overCollatDebtShares"
    );
    assertEq(
      viewFacet.getGlobalDebtValue(ctx.debtToken),
      ctx.stateBefore.debtTokenGlobalDebtValue -
        normalizeEther(_repayAmountWithoutFee, IERC20(ctx.debtToken).decimals()),
      "money market debtToken globalDebtValue"
    );
    assertEq(
      viewFacet.getFloatingBalance(ctx.debtToken),
      ctx.stateBefore.debtTokenReserve + normalizeEther(_repayAmountWithoutFee, IERC20(ctx.debtToken).decimals()),
      "money market debtToken reserve"
    );

    // check fee in debtToken to liquidationTreasury
    assertEq(
      IERC20(ctx.debtToken).balanceOf(liquidationTreasury),
      ctx.stateBefore.treasuryDebtTokenBalance + _repurchaseFee,
      "repurchase fee"
    );

    // debt token in MiniFL should be equal to debtShare after repurchased (withdrawn & burned)
    // since debt token is minted only one time, so the totalSupply should be equal to _stateAfter.debtShare after burned
    address _miniFLDebtToken = viewFacet.getDebtTokenFromToken(ctx.debtToken);
    uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(_miniFLDebtToken);
    assertEq(_miniFL.getUserTotalAmountOf(_poolId, ALICE), viewFacet.getOverCollatTokenDebtShares(ctx.debtToken));
    assertEq(DebtToken(_miniFLDebtToken).totalSupply(), viewFacet.getOverCollatTokenDebtShares(ctx.debtToken));
  }

  function testCorrectness_WhenRepurchaseDesiredLessThanDebt_ShouldWork() public makeAliceUnderwater {
    // 0.1% interest
    skip(10);

    TestRepurchaseContext memory ctx;
    ctx.borrower = ALICE;
    ctx.repurchaser = BOB;
    ctx.collatToken = address(usdc);
    ctx.debtToken = address(weth);
    // less than 1 ether (+interest) debt set by `makeAliceUnderwater`
    ctx.desiredRepayAmount = 0.9 ether;
    ctx.repurchaseFeeBps = 1000;
    ctx.collatTokenPrice = 1 ether;
    ctx.debtTokenPriceDuringRepurchase = 2 ether;
    // assume there is only 1 borrower so we can use globalPendingInterest
    ctx.borrowerPendingInterest = viewFacet.getGlobalPendingInterest(address(weth));
    _testRepurchase(ctx);
  }

  function testCorrectness_WhenRepurchaseDesiredEqualToDebt_ShouldWork() public makeAliceUnderwater {
    // 0.1% interest
    skip(10);

    TestRepurchaseContext memory ctx;
    ctx.borrower = ALICE;
    ctx.repurchaser = BOB;
    ctx.collatToken = address(usdc);
    ctx.debtToken = address(weth);
    // assume there is only 1 borrower so we can use globalPendingInterest
    ctx.borrowerPendingInterest = viewFacet.getGlobalPendingInterest(address(weth));
    // equal to 1 ether (+interest) debt set by `makeAliceUnderwater`
    ctx.desiredRepayAmount = 1 ether + ctx.borrowerPendingInterest;
    ctx.repurchaseFeeBps = 1000;
    ctx.collatTokenPrice = 1 ether;
    ctx.debtTokenPriceDuringRepurchase = 2 ether;
    _testRepurchase(ctx);
  }

  function testCorrectness_WhenRepurchaseDesiredMoreThanDebtLessThanMaxRepurchasable_ShouldWork()
    public
    makeAliceUnderwater
  {
    // 0.1% interest
    skip(10);

    TestRepurchaseContext memory ctx;
    ctx.borrower = ALICE;
    ctx.repurchaser = BOB;
    ctx.collatToken = address(usdc);
    ctx.debtToken = address(weth);
    // more than 1 ether (+interest) debt set by `makeAliceUnderwater`
    ctx.desiredRepayAmount = 1.05 ether;
    ctx.repurchaseFeeBps = 1000;
    ctx.collatTokenPrice = 1 ether;
    ctx.debtTokenPriceDuringRepurchase = 2 ether;
    // assume there is only 1 borrower so we can use globalPendingInterest
    ctx.borrowerPendingInterest = viewFacet.getGlobalPendingInterest(address(weth));
    _testRepurchase(ctx);
  }

  function testCorrectness_WhenRepurchaseDesiredMoreThanMaxRepurchasable_ShouldWork() public makeAliceUnderwater {
    // 0.01% interest
    skip(1);

    TestRepurchaseContext memory ctx;
    ctx.borrower = ALICE;
    ctx.repurchaser = BOB;
    ctx.collatToken = address(usdc);
    ctx.debtToken = address(weth);
    // more than 1.1 ether (+interest) max repurchasable set by `makeAliceUnderwater`
    ctx.desiredRepayAmount = 2 ether;
    ctx.repurchaseFeeBps = 1000;
    ctx.collatTokenPrice = 1 ether;
    ctx.debtTokenPriceDuringRepurchase = 2 ether;
    // assume there is only 1 borrower so we can use globalPendingInterest
    ctx.borrowerPendingInterest = viewFacet.getGlobalPendingInterest(address(weth));
    _testRepurchase(ctx);
  }

  function testCorrectness_WhenRepurchaseDesiredLessThanDebt_DebtAndCollatSameToken_ShouldWork()
    public
    makeAliceUnderwater
  {
    // add little weth collateral so we repurchase weth debt with weth collateral
    vm.prank(ALICE);
    accountManager.addCollateralFor(ALICE, subAccount0, address(weth), normalizeEther(0.02 ether, wethDecimal));

    // 0.01% interest
    skip(1);

    // uint256 _bobWethBalanceBefore = weth.balanceOf(BOB);

    // vm.prank(BOB);
    // liquidationFacet.repurchase(ALICE, subAccount0, address(weth), address(weth), 0.01 ether);

    // assertEq(weth.balanceOf(BOB), _bobWethBalanceBefore + 0.0001 ether);
    TestRepurchaseContext memory ctx;
    ctx.borrower = ALICE;
    ctx.repurchaser = BOB;
    ctx.collatToken = address(weth);
    ctx.debtToken = address(weth);
    ctx.desiredRepayAmount = 0.01 ether;
    ctx.repurchaseFeeBps = 1000;
    ctx.collatTokenPrice = 2 ether;
    ctx.debtTokenPriceDuringRepurchase = 2 ether;
    // assume there is only 1 borrower so we can use globalPendingInterest
    ctx.borrowerPendingInterest = viewFacet.getGlobalPendingInterest(address(weth));
    _testRepurchase(ctx);
  }

  function testRevert_WhenRepurchaseHealthySubAccount() public {
    /**
     * setup ALICE initial state
     *  - collateral 2.4 usdc (max collateral that would still allow position
     *                         to be liquidated when weth = 2 usd is 2.469... usdc)
     *  - debt 1 weth
     */
    uint256 _initialCollateralAmount = 2.4 ether;
    uint256 _initialDebtAmount = 1 ether;
    vm.startPrank(ALICE);
    accountManager.addCollateralFor(
      ALICE,
      subAccount0,
      address(usdc),
      normalizeEther(_initialCollateralAmount, usdcDecimal)
    );
    accountManager.borrow(subAccount0, address(weth), _initialDebtAmount);
    vm.stopPrank();

    /**
     * weth price 1 usd
     * ALICE position is not repurchasable
     *  - totalBorrowingPower = sum(collatAmount * price * collatFactor)
     *                        = 2.4 * 1 * 9000 = 21600
     *  - usedBorrowingPower = sum(debtAmount * price / borrowFactor)
     *                       = 1 * 1 / 0.9 = 11111
     */
    vm.prank(BOB);
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Healthy.selector));
    liquidationFacet.repurchase(
      ALICE,
      subAccount0,
      address(weth),
      address(usdc),
      normalizeEther(0.1 ether, wethDecimal)
    );
  }

  function testRevert_WhenRepurchaserIsNotOk() public makeAliceUnderwater {
    // make sure that BOB is not ok
    address[] memory _repurchasers = new address[](1);
    _repurchasers[0] = BOB;
    adminFacet.setRepurchasersOk(_repurchasers, false);

    vm.prank(BOB);
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Unauthorized.selector));
    liquidationFacet.repurchase(
      ALICE,
      subAccount0,
      address(weth),
      address(usdc),
      normalizeEther(0.1 ether, wethDecimal)
    );
  }

  function testRevert_WhenRepurchaseRepayAmountExceedThreshold() public makeAliceUnderwater {
    // can't repay more than 0.01% of borrowingPower
    adminFacet.setLiquidationParams(1, 10000);

    vm.prank(BOB);
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_RepayAmountExceedThreshold.selector));
    liquidationFacet.repurchase(
      ALICE,
      subAccount0,
      address(weth),
      address(usdc),
      normalizeEther(0.1 ether, wethDecimal)
    );
  }

  function testRevert_WhenRepurchaseCollateralNotEnoughToCoverDesiredRepayAmount() public makeAliceUnderwater {
    // reset weth price back 1 usd to allow ALICE to remove collateral
    mockOracle.setTokenPrice(address(weth), 1 ether);
    vm.prank(ALICE);
    // remove 0.4 usdc collateral to make it insufficient for desiredRepayAmount > 1 weth
    accountManager.removeCollateral(subAccount0, address(usdc), normalizeEther(0.4 ether, usdcDecimal));

    /**
     * weth price change 1 usd -> 2 usd
     * ALICE position become repurchasable
     *  - totalBorrowingPower = sum(collatAmount * price * collatFactor)
     *                        = 2 * 1 * 9000 = 18000
     *  - usedBorrowingPower = sum(debtAmount * price / borrowFactor)
     *                       = 1 * 2 / 0.9 = 22222
     */
    mockOracle.setTokenPrice(address(weth), 2 ether);

    /**
     * collatAmount = 2 usdc
     * desiredRepayAmount = 1.1 weth
     * collatAmountOut = repayAmount * repayTokenPriceWithPremium / collatTokenPrice
     *                 = 1.1 * 2.02 / 1 = 2.222 usdc
     * insufficient collat out (collatAmountOut > collatAmount)
     */
    vm.prank(BOB);
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_InsufficientAmount.selector));
    liquidationFacet.repurchase(
      ALICE,
      subAccount0,
      address(weth),
      address(usdc),
      normalizeEther(1.1 ether, wethDecimal)
    );
  }

  function testFuzz_RepurchaseCalculation(uint256 _desiredRepayAmount) public makeAliceUnderwater {
    // assume no interest

    /**
     * this input setup will cover 2 cases for desiredRepayAmount
     *   1) desiredRepayAmount <= maxAmountRepurchaseable
     *   2) desiredRepayAmount > maxAmountRepurchaseable
     * where maxAmountRepurchaseable = 1.1 ether (calculation below)
     */
    _desiredRepayAmount = bound(_desiredRepayAmount, 0, 1.6 ether);

    TestRepurchaseContext memory ctx;
    ctx.borrower = ALICE;
    ctx.repurchaser = BOB;
    ctx.collatToken = address(usdc);
    ctx.debtToken = address(weth);
    ctx.desiredRepayAmount = _desiredRepayAmount;
    ctx.repurchaseFeeBps = 1000;
    ctx.collatTokenPrice = 1 ether;
    ctx.debtTokenPriceDuringRepurchase = 2 ether;
    _testRepurchase(ctx);
  }

  function testFuzz_ConsecutiveRepurchase(uint256[3] memory desiredRepayAmounts) public makeAliceUnderwater {
    // assume no interest

    // bound input to small amount to partially repurchase while
    // not making position healthy to allow final full repurchase
    for (uint256 i; i < desiredRepayAmounts.length; ++i) {
      desiredRepayAmounts[i] = bound(desiredRepayAmounts[i], 0, 0.05 ether);
    }

    TestRepurchaseContext memory ctx;
    ctx.borrower = ALICE;
    ctx.repurchaser = BOB;
    ctx.collatToken = address(usdc);
    ctx.debtToken = address(weth);
    ctx.repurchaseFeeBps = 1000;
    ctx.collatTokenPrice = 1 ether;
    ctx.debtTokenPriceDuringRepurchase = 2 ether;

    uint256 _treasuryBalanceBefore = weth.balanceOf(liquidationTreasury);

    // partially repurchase 3 times
    // followed by full repurchase to clear all debt
    for (uint256 i; i < desiredRepayAmounts.length; ++i) {
      ctx.desiredRepayAmount = desiredRepayAmounts[i];
      _testRepurchase(ctx);
    }
    ctx.desiredRepayAmount = type(uint256).max;
    _testRepurchase(ctx);

    // expect no debt remain
    (, uint256 _debtAmountAfter) = viewFacet.getOverCollatDebtShareAndAmountOf(
      ctx.borrower,
      subAccount0,
      ctx.debtToken
    );
    assertEq(_debtAmountAfter, 0, "borrower final debt");

    // expect total repurchase fee = max fee
    uint256 _maxFee = 0.1 ether;
    assertApproxEqAbs(weth.balanceOf(liquidationTreasury), _treasuryBalanceBefore + _maxFee, 3, "max fee");
  }
}
