// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, DebtToken, console } from "../MoneyMarket_BaseTest.t.sol";

// libs
import { LibConstant } from "../../../contracts/money-market/libraries/LibConstant.sol";
import { LibShareUtil } from "../../../contracts/money-market/libraries/LibShareUtil.sol";

// interfaces
import { IAdminFacet } from "../../../contracts/money-market/interfaces/IAdminFacet.sol";
import { ILiquidationFacet } from "../../../contracts/money-market/interfaces/ILiquidationFacet.sol";

import { IMiniFL } from "../../../contracts/money-market/interfaces/IMiniFL.sol";
import { IERC20 } from "solidity/contracts/money-market/interfaces/IERC20.sol";

// contracts
import { FixedFeeModel } from "../../../contracts/money-market/fee-models/FixedFeeModel.sol";

// mocks
import { MockInterestModel } from "solidity/tests/mocks/MockInterestModel.sol";

contract MoneyMarket_Liquidation_RepurchaseTest is MoneyMarket_BaseTest {
  IMiniFL internal _miniFL;
  uint16 internal constant REPURCHASE_FEE = 1000;

  function setUp() public override {
    super.setUp();

    _miniFL = IMiniFL(address(miniFL));

    // initial prices: 1 weth = 1 usd, 1 usdc = 1 usd
    mockOracle.setTokenPrice(address(weth), 1 ether);
    mockOracle.setTokenPrice(address(usdc), 1 ether);
    // all token have collatFactor 9000, borrowFactor 9000
    address[] memory _tokens = new address[](2);
    _tokens[0] = address(weth);
    _tokens[1] = address(usdc);
    IAdminFacet.TokenConfigInput[] memory _tokenConfigInputs = new IAdminFacet.TokenConfigInput[](2);
    _tokenConfigInputs[0] = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxCollateral: 1e40,
      maxBorrow: 1e40
    });
    _tokenConfigInputs[1] = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxCollateral: 1e40,
      maxBorrow: 1e40
    });
    adminFacet.setTokenConfigs(_tokens, _tokenConfigInputs);
    // 10% repurchase fee
    adminFacet.setFees(0, REPURCHASE_FEE, 0, 0);
    // 1% repurchase reward (hard-coded in FixedFeeModel)
    FixedFeeModel fixedFeeModel = new FixedFeeModel();
    adminFacet.setRepurchaseRewardModel(fixedFeeModel);
    // allow to repurchase up to 100% of position
    adminFacet.setLiquidationParams(10000, 10000);
    // fixed 0.01% (1 bps = 1e16) interest per block for all token
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

  function _makeAliceUnderwater() internal {
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
     *                        = 2.4 * 1 * 0.9 = 2.16
     *  - usedBorrowingPower = sum(debtAmount * price / borrowFactor)
     *                       = 1 * 2 / 0.9 = 1 * 2 / 0.9 = 2.222...
     */
    mockOracle.setTokenPrice(address(weth), 2 ether);
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

  struct TestRepurchaseLocalVarCalculation {
    uint256 repayAmountWithFee;
    uint256 repayAmountWithoutFee;
    uint256 repayTokenPriceWithPremium;
    uint256 collatSold;
    uint256 repurchaseFee;
    uint256 actualRepurchaserRepayAmount;
    uint256 expectRepayShare;
    uint256 actualDebtRepay;
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
    TestRepurchaseLocalVarCalculation memory _vars;
    {
      uint256 _maxAmountRepurchasable = (ctx.stateBefore.borrowerDebtAmount * (10000 + ctx.repurchaseFeeBps)) / 10000;
      // case 1
      if (ctx.desiredRepayAmount > _maxAmountRepurchasable) {
        _vars.repayAmountWithFee = _maxAmountRepurchasable;
        _vars.repayAmountWithoutFee = ctx.stateBefore.borrowerDebtAmount;
      } else {
        // case 2
        _vars.repayAmountWithFee = ctx.desiredRepayAmount;
        _vars.repayAmountWithoutFee = (ctx.desiredRepayAmount * 10000) / (10000 + (ctx.repurchaseFeeBps));
      }
    }
    _vars.repurchaseFee = _vars.repayAmountWithFee - _vars.repayAmountWithoutFee;
    _vars.actualRepurchaserRepayAmount = _vars.repayAmountWithFee;
    _vars.actualDebtRepay = _vars.repayAmountWithoutFee;
    {
      uint256 _actualRepayShare = LibShareUtil.valueToShare(
        _vars.repayAmountWithoutFee,
        ctx.stateBefore.debtTokenOverCollatDebtShares,
        ctx.stateBefore.debtTokenOverCollatDebtAmount
      );

      _vars.expectRepayShare = LibShareUtil.valueToShareRoundingUp(
        _vars.repayAmountWithoutFee,
        ctx.stateBefore.debtTokenOverCollatDebtShares,
        ctx.stateBefore.debtTokenOverCollatDebtAmount
      );
      if (_actualRepayShare + 1 == _vars.expectRepayShare) {
        _vars.actualRepurchaserRepayAmount = _vars.repayAmountWithFee + 1;
        _vars.actualDebtRepay = _vars.repayAmountWithoutFee + 1;
      }
    }
    // constant 1% premium
    _vars.repayTokenPriceWithPremium = (ctx.debtTokenPriceDuringRepurchase * (10000 + 100)) / 10000;
    _vars.collatSold = (_vars.repayAmountWithFee * _vars.repayTokenPriceWithPremium) / ctx.collatTokenPrice;

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
        ctx.stateBefore.borrowerCollateralAmount - normalizeEther(_vars.collatSold, IERC20(ctx.collatToken).decimals()),
        "borrower remaining collat"
      );
      (uint256 _debtSharesAfter, uint256 _debtAmountAfter) = viewFacet.getOverCollatDebtShareAndAmountOf(
        ctx.borrower,
        subAccount0,
        ctx.debtToken
      );
      assertEq(
        _debtAmountAfter,
        ctx.stateBefore.borrowerDebtAmount -
          normalizeEther(_vars.repayAmountWithoutFee, IERC20(ctx.debtToken).decimals()),
        "borrower remaining debt amount"
      );
      assertEq(
        _debtSharesAfter,
        ctx.stateBefore.borrowerDebtShares - normalizeEther(_vars.expectRepayShare, IERC20(ctx.debtToken).decimals()),
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
          normalizeEther(_vars.collatSold, IERC20(ctx.collatToken).decimals()) -
          normalizeEther(_vars.repayAmountWithFee, IERC20(ctx.debtToken).decimals()),
        "collatToken == debtToken: repurchaser collatToken received"
      );
    } else {
      assertEq(
        IERC20(ctx.collatToken).balanceOf(ctx.repurchaser),
        ctx.stateBefore.repurchaserCollatTokenBalance +
          normalizeEther(_vars.collatSold, IERC20(ctx.collatToken).decimals()),
        "repurchaser collatToken received"
      );
      assertEq(
        IERC20(ctx.debtToken).balanceOf(ctx.repurchaser),
        ctx.stateBefore.repurchaserDebtTokenBalance -
          normalizeEther(_vars.actualRepurchaserRepayAmount, IERC20(ctx.debtToken).decimals()),
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
        normalizeEther(_vars.actualDebtRepay, IERC20(ctx.debtToken).decimals()),
      "money market debtToken overCollatDebtValue"
    );
    assertEq(
      viewFacet.getOverCollatTokenDebtShares(ctx.debtToken),
      ctx.stateBefore.debtTokenOverCollatDebtShares -
        normalizeEther(_vars.expectRepayShare, IERC20(ctx.debtToken).decimals()),
      "money market debtToken overCollatDebtShares"
    );
    assertEq(
      viewFacet.getGlobalDebtValue(ctx.debtToken),
      ctx.stateBefore.debtTokenGlobalDebtValue -
        normalizeEther(_vars.actualDebtRepay, IERC20(ctx.debtToken).decimals()),
      "money market debtToken globalDebtValue"
    );
    assertEq(
      viewFacet.getFloatingBalance(ctx.debtToken),
      ctx.stateBefore.debtTokenReserve + normalizeEther(_vars.actualDebtRepay, IERC20(ctx.debtToken).decimals()),
      "money market debtToken reserve"
    );

    // check fee in debtToken to liquidationTreasury
    assertEq(
      IERC20(ctx.debtToken).balanceOf(liquidationTreasury),
      ctx.stateBefore.treasuryDebtTokenBalance + _vars.repurchaseFee,
      "repurchase fee"
    );

    // debt token in MiniFL should be equal to debtShare after repurchased (withdrawn & burned)
    // since debt token is minted only one time, so the totalSupply should be equal to _stateAfter.debtShare after burned
    address _miniFLDebtToken = viewFacet.getDebtTokenFromToken(ctx.debtToken);
    uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(_miniFLDebtToken);
    assertEq(_miniFL.getStakingReserves(_poolId), viewFacet.getOverCollatTokenDebtShares(ctx.debtToken));
    assertEq(DebtToken(_miniFLDebtToken).totalSupply(), viewFacet.getOverCollatTokenDebtShares(ctx.debtToken));
  }

  function testCorrectness_WhenRepurchaseDesiredLessThanDebt_ShouldWork() public {
    _makeAliceUnderwater();

    // 0.1% interest
    skip(10);

    TestRepurchaseContext memory ctx;
    ctx.borrower = ALICE;
    ctx.repurchaser = BOB;
    ctx.collatToken = address(usdc);
    ctx.debtToken = address(weth);
    // less than 1 ether (+interest) debt set by `makeAliceUnderwater`
    ctx.desiredRepayAmount = 0.9 ether;
    ctx.repurchaseFeeBps = REPURCHASE_FEE;
    ctx.collatTokenPrice = 1 ether;
    ctx.debtTokenPriceDuringRepurchase = 2 ether;
    // assume there is only 1 borrower so we can use globalPendingInterest
    ctx.borrowerPendingInterest = viewFacet.getGlobalPendingInterest(address(weth));
    _testRepurchase(ctx);
  }

  function testCorrectness_WhenRepurchaseDesiredEqualToDebt_ShouldWork() public {
    _makeAliceUnderwater();

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
    ctx.repurchaseFeeBps = REPURCHASE_FEE;
    ctx.collatTokenPrice = 1 ether;
    ctx.debtTokenPriceDuringRepurchase = 2 ether;
    _testRepurchase(ctx);
  }

  function testCorrectness_WhenRepurchaseDesiredMoreThanDebtLessThanMaxRepurchasable_ShouldWork() public {
    _makeAliceUnderwater();

    // 0.1% interest
    skip(10);

    TestRepurchaseContext memory ctx;
    ctx.borrower = ALICE;
    ctx.repurchaser = BOB;
    ctx.collatToken = address(usdc);
    ctx.debtToken = address(weth);
    // more than 1 ether (+interest) debt set by `makeAliceUnderwater`
    ctx.desiredRepayAmount = 1.05 ether;
    ctx.repurchaseFeeBps = REPURCHASE_FEE;
    ctx.collatTokenPrice = 1 ether;
    ctx.debtTokenPriceDuringRepurchase = 2 ether;
    // assume there is only 1 borrower so we can use globalPendingInterest
    ctx.borrowerPendingInterest = viewFacet.getGlobalPendingInterest(address(weth));
    _testRepurchase(ctx);
  }

  function testCorrectness_WhenRepurchaseDesiredMoreThanMaxRepurchasable_ShouldWork() public {
    _makeAliceUnderwater();

    // 0.01% interest
    skip(1);

    TestRepurchaseContext memory ctx;
    ctx.borrower = ALICE;
    ctx.repurchaser = BOB;
    ctx.collatToken = address(usdc);
    ctx.debtToken = address(weth);
    // more than 1.1 ether (+interest) max repurchasable set by `makeAliceUnderwater`
    ctx.desiredRepayAmount = 2 ether;
    ctx.repurchaseFeeBps = REPURCHASE_FEE;
    ctx.collatTokenPrice = 1 ether;
    ctx.debtTokenPriceDuringRepurchase = 2 ether;
    // assume there is only 1 borrower so we can use globalPendingInterest
    ctx.borrowerPendingInterest = viewFacet.getGlobalPendingInterest(address(weth));
    _testRepurchase(ctx);
  }

  function testCorrectness_WhenRepurchaseDesiredLessThanDebt_DebtAndCollatSameToken_ShouldWork() public {
    _makeAliceUnderwater();

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
    ctx.repurchaseFeeBps = REPURCHASE_FEE;
    ctx.collatTokenPrice = 2 ether;
    ctx.debtTokenPriceDuringRepurchase = 2 ether;
    // assume there is only 1 borrower so we can use globalPendingInterest
    ctx.borrowerPendingInterest = viewFacet.getGlobalPendingInterest(address(weth));
    _testRepurchase(ctx);
  }

  function testRevert_WhenRepurchaseHealthySubAccount() public {
    _makeAliceUnderwater();

    mockOracle.setTokenPrice(address(weth), 1 ether);

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

  function testRevert_WhenRepurchaserIsNotOk() public {
    _makeAliceUnderwater();

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

  function testRevert_WhenRepurchaseRepayAmountExceedThreshold() public {
    _makeAliceUnderwater();

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

  function testRevert_WhenRepurchaseCollateralNotEnoughToCoverDesiredRepayAmount() public {
    _makeAliceUnderwater();

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

  function testFuzz_RepurchaseCalculation(uint256 _desiredRepayAmount) public {
    /**
     * this input setup will cover 2 cases for desiredRepayAmount
     *   1) desiredRepayAmount <= maxAmountRepurchaseable
     *   2) desiredRepayAmount > maxAmountRepurchaseable
     * where maxAmountRepurchaseable = 1.1 ether (calculation below)
     */
    _desiredRepayAmount = bound(_desiredRepayAmount, 0, 1.6 ether);

    _makeAliceUnderwater();

    // assume no interest

    TestRepurchaseContext memory ctx;
    ctx.borrower = ALICE;
    ctx.repurchaser = BOB;
    ctx.collatToken = address(usdc);
    ctx.debtToken = address(weth);
    ctx.desiredRepayAmount = _desiredRepayAmount;
    ctx.repurchaseFeeBps = REPURCHASE_FEE;
    ctx.collatTokenPrice = 1 ether;
    ctx.debtTokenPriceDuringRepurchase = 2 ether;
    _testRepurchase(ctx);
  }

  function testFuzz_ConsecutiveRepurchase(uint256[3] memory desiredRepayAmounts) public {
    // bound input to small amount to partially repurchase while
    // not making position healthy to allow final full repurchase
    for (uint256 i; i < desiredRepayAmounts.length; ++i) {
      desiredRepayAmounts[i] = bound(desiredRepayAmounts[i], 0, 0.05 ether);
    }

    // assume no interest

    _makeAliceUnderwater();

    TestRepurchaseContext memory ctx;
    ctx.borrower = ALICE;
    ctx.repurchaser = BOB;
    ctx.collatToken = address(usdc);
    ctx.debtToken = address(weth);
    ctx.repurchaseFeeBps = REPURCHASE_FEE;
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

  function testRevert_SelfRepurchase_ShouldRevert() external {
    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Unauthorized.selector));
    liquidationFacet.repurchase(ALICE, 0, address(usdc), address(usdc), 1);
  }

  function testCorrectness_WhenRepurchaseEntireDebtWithPrecisionLoss_NoDebtRemainInSubAccount() public {
    _makeAliceUnderwater();

    // 0.01% interest
    skip(1);

    // make BOB borrow another 0.1 weth to cause precision loss when alice'debt got repurchase
    adminFacet.setMinDebtSize(0);
    vm.startPrank(BOB);
    accountManager.depositAndAddCollateral(subAccount0, address(weth), 1 ether);
    accountManager.borrow(subAccount0, address(weth), 0.1 ether);
    vm.stopPrank();

    TestRepurchaseContext memory ctx;
    ctx.borrower = ALICE;
    ctx.repurchaser = BOB;
    ctx.collatToken = address(usdc);
    ctx.debtToken = address(weth);
    // more than 1.1 ether (+interest) max repurchasable set by `makeAliceUnderwater`
    ctx.desiredRepayAmount = 2 ether;
    ctx.repurchaseFeeBps = REPURCHASE_FEE;
    ctx.collatTokenPrice = 1 ether;
    ctx.debtTokenPriceDuringRepurchase = 2 ether;
    ctx.borrowerPendingInterest = viewFacet.getGlobalPendingInterest(address(weth));
    _testRepurchase(ctx);
  }
}

// pragma solidity 0.8.17;

// import { MoneyMarket_BaseTest, MockERC20, DebtToken, console } from "../MoneyMarket_BaseTest.t.sol";

// // libs
// import { LibMoneyMarket01 } from "../../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// // interfaces
// import { IBorrowFacet, LibDoublyLinkedList } from "../../../contracts/money-market/facets/BorrowFacet.sol";
// import { ILiquidationFacet } from "../../../contracts/money-market/interfaces/ILiquidationFacet.sol";
// import { IAdminFacet } from "../../../contracts/money-market/interfaces/IAdminFacet.sol";
// import { TripleSlopeModel6, IInterestRateModel } from "../../../contracts/money-market/interest-models/TripleSlopeModel6.sol";
// import { FixedFeeModel, IFeeModel } from "../../../contracts/money-market/fee-models/FixedFeeModel.sol";
// import { IMiniFL } from "../../../contracts/money-market/interfaces/IMiniFL.sol";

// struct CacheState {
//   uint256 collat;
//   uint256 subAccountCollat;
//   uint256 debtShare;
//   uint256 debtValue;
//   uint256 subAccountDebtShare;
// }

// contract MoneyMarket_Liquidation_RepurchaseTest is MoneyMarket_BaseTest {
//   using LibDoublyLinkedList for LibDoublyLinkedList.List;
//   uint256 _subAccountId = 0;
//   address _aliceSubAccount0 = LibMoneyMarket01.getSubAccount(ALICE, _subAccountId);
//   IMiniFL internal _miniFL;

//   function setUp() public override {
//     super.setUp();

//     _miniFL = IMiniFL(address(miniFL));

//     TripleSlopeModel6 _tripleSlope6 = new TripleSlopeModel6();
//     adminFacet.setInterestModel(address(weth), address(_tripleSlope6));
//     adminFacet.setInterestModel(address(btc), address(_tripleSlope6));
//     adminFacet.setInterestModel(address(usdc), address(_tripleSlope6));

//     FixedFeeModel fixedFeeModel = new FixedFeeModel();
//     adminFacet.setRepurchaseRewardModel(fixedFeeModel);

//     vm.startPrank(DEPLOYER);
//     mockOracle.setTokenPrice(address(btc), normalizeEther(10 ether, btcDecimal));
//     vm.stopPrank();

//     // bob deposit 100 usdc and 10 btc
//     vm.startPrank(BOB);
//     accountManager.deposit(address(usdc), normalizeEther(100 ether, usdcDecimal));
//     accountManager.deposit(address(btc), normalizeEther(10 ether, btcDecimal));
//     vm.stopPrank();

//     vm.startPrank(ALICE);
//     accountManager.addCollateralFor(ALICE, 0, address(weth), normalizeEther(40 ether, wethDecimal));
//     // alice added collat 40 ether
//     // given collateralFactor = 9000, weth price = 1
//     // then alice got power = 40 * 1 * 9000 / 10000 = 36 ether USD
//     // alice borrowed 30% of vault then interest should be 0.0617647058676 per year
//     // interest per day = 0.00016921837224
//     accountManager.borrow(0, address(usdc), normalizeEther(30 ether, usdcDecimal));
//     vm.stopPrank();
//   }

//   function testCorrectness_ShouldRepurchasePassed_TransferTokenCorrectly() external {
//     // criteria
//     address _debtToken = address(usdc);
//     address _collatToken = address(weth);

//     uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);
//     uint256 _bobWethBalanceBefore = weth.balanceOf(BOB);

//     // collat amount should be = 40
//     // collat debt value should be = 30
//     // collat debt share should be = 30
//     CacheState memory _stateBefore = CacheState({
//       collat: viewFacet.getTotalCollat(_collatToken),
//       subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, _collatToken),
//       debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
//       debtValue: viewFacet.getOverCollatTokenDebtValue(_debtToken),
//       subAccountDebtShare: 0
//     });
//     (_stateBefore.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, _debtToken);
//     console.log(_stateBefore.debtShare);
//     console.log(_stateBefore.debtValue);
//     console.log(MockERC20(_debtToken).balanceOf(liquidationTreasury));

//     uint256 _treasuryFeeBefore = MockERC20(_debtToken).balanceOf(liquidationTreasury);

//     // add time 1 day
//     // then total debt value should increase by 0.00016921837224 * 30 = 0.0050765511672
//     vm.warp(block.timestamp + 1 days);

//     // set price to weth from 1 to 0.8 ether USD
//     // then alice borrowing power = 40 * 0.8 * 9000 / 10000 = 28.8 ether USD
//     mockOracle.setTokenPrice(address(usdc), normalizeEther(1 ether, usdDecimal));
//     mockOracle.setTokenPrice(address(weth), normalizeEther(8e17, usdDecimal));
//     mockOracle.setTokenPrice(address(btc), normalizeEther(10 ether, usdDecimal));

//     // bob try repurchase with 15 usdc
//     // eth price = 0.8 USD
//     // usdc price = 1 USD
//     // reward = 1%
//     // repurchase fee = 1%
//     // timestamp increased by 1 day, debt value should increased to 30.005076
//     // repaid = desired / (1 + feePct) = 15 / (1 + 0.01) = 14.85[1485]...
//     // fee amount = desired - repaid = 15 - 14.85[1485]... = 0.1485[1485]... ~ 0.148515 usdc
//     uint256 _expectedFee = normalizeEther(0.148515 ether, usdcDecimal);
//     vm.prank(BOB, BOB);
//     liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, normalizeEther(15 ether, usdcDecimal));

//     // repay value = 15 * 1 = 1 USD
//     // reward amount = 15 * 1.01 = 15.15 USD
//     // converted weth amount = 15.15 / 0.8 = 18.9375

//     uint256 _bobUsdcBalanceAfter = usdc.balanceOf(BOB);
//     uint256 _bobWethBalanceAfter = weth.balanceOf(BOB);

//     // check bob balance
//     assertEq(_bobUsdcBalanceBefore - _bobUsdcBalanceAfter, normalizeEther(15 ether, usdcDecimal)); // pay 15 usdc
//     assertEq(_bobWethBalanceAfter - _bobWethBalanceBefore, normalizeEther(18.9375 ether, wethDecimal)); // get 18.9375 weth

//     CacheState memory _stateAfter = CacheState({
//       collat: viewFacet.getTotalCollat(_collatToken),
//       subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, _collatToken),
//       debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
//       debtValue: viewFacet.getOverCollatTokenDebtValue(_debtToken),
//       subAccountDebtShare: 0
//     });
//     (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, _debtToken);

//     // check state
//     // note: before repurchase state should be like these
//     // collat amount should be = 40
//     // collat debt value should be = 30.005076 (0.0050765511672 is fixed interest increased)
//     // collat debt share should be = 30
//     // then after repurchase
//     // collat amount should be = 40 - (_collatAmountOut) = 40 - 18.9375 = 21.0625
//     // actual repaid debt amount = 14.85[1485]...
//     // collat debt value should be = 30.005076 - (actual repaid debt amount) = 30.005076 - 14.85[1485]... = 15.15359085[1485]...
//     // _repayShare = actual repaid debt amount * totalDebtShare / totalDebtValue = 14.85[1485]... * 30 / 30.005076 = 14.84897270233
//     // collat debt share should be = 30 - (_repayShare) = 30 - 14.84897270233 = 15.151027
//     assertEq(_stateAfter.collat, normalizeEther(21.0625 ether, wethDecimal));
//     assertEq(_stateAfter.subAccountCollat, normalizeEther(21.0625 ether, wethDecimal));
//     assertEq(_stateAfter.debtValue, normalizeEther(15.153591 ether, usdcDecimal));
//     assertEq(_stateAfter.debtShare, normalizeEther(15.151028 ether, usdcDecimal));
//     assertEq(_stateAfter.subAccountDebtShare, normalizeEther(15.151028 ether, usdcDecimal));
//     // globalDebt should equal to debtValue since there is only 1 position
//     assertEq(viewFacet.getGlobalDebtValue(_debtToken), normalizeEther(15.153591 ether, usdcDecimal));
//     vm.stopPrank();

//     assertEq(MockERC20(_debtToken).balanceOf(liquidationTreasury) - _treasuryFeeBefore, _expectedFee);

//     // debt token in MiniFL should be equal to debtShare after repurchased (withdrawn & burned)
//     // since debt token is minted only one time, so the totalSupply should be equal to _stateAfter.debtShare after burned
//     address _miniFLDebtToken = viewFacet.getDebtTokenFromToken(_debtToken);
//     uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(_miniFLDebtToken);
//     assertEq(_miniFL.getUserTotalAmountOf(_poolId, ALICE), _stateAfter.debtShare);
//     assertEq(DebtToken(_miniFLDebtToken).totalSupply(), _stateAfter.debtShare);
//   }

//   function testCorrectness_ShouldRepurchasePassedWithMoreThan50PercentOfDebtToken_TransferTokenCorrectly() external {
//     // alice add more collateral
//     vm.startPrank(ALICE);
//     accountManager.addCollateralFor(ALICE, 0, address(weth), normalizeEther(40 ether, wethDecimal));
//     // alice borrow more btc token as 30% of vault = 3 btc
//     accountManager.borrow(0, address(btc), normalizeEther(3 ether, btcDecimal));
//     vm.stopPrank();

//     // criteria
//     address _debtToken = address(usdc);
//     address _collatToken = address(weth);

//     uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);
//     uint256 _bobWethBalanceBefore = weth.balanceOf(BOB);

//     // collat amount should be = 80 on weth
//     // collat debt value should be | usdc: 30 | btc: 3 |
//     // collat debt share should be | usdc: 30 | btc: 3 |
//     CacheState memory _stateBefore = CacheState({
//       collat: viewFacet.getTotalCollat(_collatToken),
//       subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, _collatToken),
//       debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
//       debtValue: viewFacet.getOverCollatTokenDebtValue(_debtToken),
//       subAccountDebtShare: 0
//     });
//     (_stateBefore.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, _debtToken);

//     uint256 _treasuryFeeBefore = MockERC20(_debtToken).balanceOf(liquidationTreasury);

//     // add time 1 day
//     // 0.00016921837224 is interest rate per day of (30% condition slope)
//     // then total debt value of usdc should increase by 0.00016921837224 * 30 = 0.0050765511672
//     // then total debt value of btc should increase by 0.00016921837224 * 3 = 0.00050765511672
//     vm.warp(block.timestamp + 1 days);

//     // set price to weth from 1 to 0.8 ether USD
//     // then alice borrowing power = 40 * 0.8 * 9000 / 10000 = 28.8 ether USD
//     vm.prank(DEPLOYER);
//     mockOracle.setTokenPrice(address(weth), 8e17);
//     mockOracle.setTokenPrice(address(usdc), 1e18);
//     mockOracle.setTokenPrice(address(btc), 10e18);
//     vm.stopPrank();

//     // bob try repurchase with 20 usdc
//     // eth price = 0.8 USD
//     // usdc price = 1 USD
//     // reward = 1%
//     // repurchase fee = 1%
//     // timestamp increased by 1 day, usdc debt value should increased to 30.0050765511672
//     // timestamp increased by 1 day, btc value should increased to 3.00050765511672
//     // repaid = desired / (1 + feePct) = 20 / (1 + 0.01) = 19.801[9801]...
//     // fee amount = desired - repaid = 20 - 19.801[9801]... = 0.19801[9801]... ~ 0.198020 usdc
//     uint256 _expectedFee = normalizeEther(0.198020 ether, usdcDecimal);
//     vm.prank(BOB, BOB);
//     liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, normalizeEther(20 ether, usdcDecimal));

//     // repay value = 20 * 1 = 1 USD
//     // reward amount = 20 * 1.01 = 20.20 USD
//     // converted weth amount = 20.20 / 0.8 = 25.25
//     // fee amount = 20 * 0.01 = 0.2 ether

//     uint256 _bobUsdcBalanceAfter = usdc.balanceOf(BOB);
//     uint256 _bobWethBalanceAfter = weth.balanceOf(BOB);

//     // check bob balance
//     assertEq(_bobUsdcBalanceBefore - _bobUsdcBalanceAfter, normalizeEther(20 ether, usdcDecimal)); // pay 20 usdc
//     assertEq(_bobWethBalanceAfter - _bobWethBalanceBefore, normalizeEther(25.25 ether, wethDecimal)); // get 25.25 weth

//     CacheState memory _stateAfter = CacheState({
//       collat: viewFacet.getTotalCollat(_collatToken),
//       subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, _collatToken),
//       debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
//       debtValue: viewFacet.getOverCollatTokenDebtValue(_debtToken),
//       subAccountDebtShare: 0
//     });
//     (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, _debtToken);

//     // check state
//     // note: before repurchase state should be like these
//     // collat amount should be = 80 on weth
//     // collat debt value should be | usdc: 30.005076 | btc: 3.00050765511672 | after accure interest
//     // collat debt share should be | usdc: 30 | btc: 3 |
//     // then after repurchase
//     // collat amount should be = 80 - (_collatAmountOut) = 80 - 25.25 = 54.75
//     // actual repaid debt amount = 20 / (1 + 0.01)
//     // collat debt value should be = 30.005076 - (actual repaid debt amount) = 30.005076 - 20 / (1 + 0.01) ~ 10.203096
//     // _repayShare = (actual repaid debt amount) * totalDebtShare / totalDebtValue = 20 / (1 + 0.01) * 30 / 30.005076
//     // collat debt share should be = 30 - (_repayShare) = 30 - (20 / (1 + 0.01) * 30 / 30.005076) ~ 10.201370
//     assertEq(_stateAfter.collat, normalizeEther(54.75 ether, wethDecimal));
//     assertEq(_stateAfter.subAccountCollat, normalizeEther(54.75 ether, wethDecimal));
//     assertEq(_stateAfter.debtValue, normalizeEther(10.203096 ether, usdcDecimal));
//     assertEq(_stateAfter.debtShare, normalizeEther(10.201370 ether, usdcDecimal));
//     assertEq(_stateAfter.subAccountDebtShare, normalizeEther(10.201370 ether, usdcDecimal));

//     // check state for btc should not be changed
//     CacheState memory _btcState = CacheState({
//       collat: viewFacet.getTotalCollat(address(btc)),
//       subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, address(btc)),
//       debtShare: viewFacet.getOverCollatTokenDebtShares(address(btc)),
//       debtValue: viewFacet.getOverCollatTokenDebtValue(address(btc)),
//       subAccountDebtShare: 0
//     });
//     (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, address(btc));
//     assertEq(_btcState.collat, 0);
//     assertEq(_btcState.subAccountCollat, 0);
//     assertEq(_btcState.debtValue, normalizeEther(3.00050765511672 ether, btcDecimal));
//     assertEq(_btcState.debtShare, normalizeEther(3 ether, btcDecimal));

//     assertEq(MockERC20(_debtToken).balanceOf(liquidationTreasury) - _treasuryFeeBefore, _expectedFee);

//     // debt token in MiniFL should be equal to debtShare after repurchased (withdrawn & burned)
//     // since debt token is minted only one time, so the totalSupply should be equal to _stateAfter.debtShare after burned
//     address _miniFLDebtToken = viewFacet.getDebtTokenFromToken(_debtToken);
//     uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(_miniFLDebtToken);
//     assertEq(_miniFL.getUserTotalAmountOf(_poolId, ALICE), _stateAfter.debtShare);
//     assertEq(DebtToken(_miniFLDebtToken).totalSupply(), _stateAfter.debtShare);
//   }

//   function testCorrectness_ShouldRepurchasePassedWithMoreThanDebtTokenAmount_TransferTokenCorrectly() external {
//     // alice add more collateral
//     vm.startPrank(ALICE);
//     accountManager.addCollateralFor(ALICE, 0, address(weth), normalizeEther(60 ether, wethDecimal));
//     // alice borrow more btc token as 50% of vault = 5 btc
//     accountManager.borrow(0, address(btc), normalizeEther(5 ether, btcDecimal));
//     vm.stopPrank();

//     // criteria
//     address _debtToken = address(usdc);
//     address _collatToken = address(weth);

//     uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);
//     uint256 _bobWethBalanceBefore = weth.balanceOf(BOB);

//     // collat amount should be = 100 on weth
//     // collat debt value should be | usdc: 30 | btc: 5 |
//     // collat debt share should be | usdc: 30 | btc: 5 |
//     CacheState memory _stateBefore = CacheState({
//       collat: viewFacet.getTotalCollat(_collatToken),
//       subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, _collatToken),
//       debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
//       debtValue: viewFacet.getOverCollatTokenDebtValue(_debtToken),
//       subAccountDebtShare: 0
//     });
//     (_stateBefore.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, _debtToken);

//     uint256 _treasuryFeeBefore = MockERC20(_debtToken).balanceOf(liquidationTreasury);

//     // set price to weth from 1 to 0.8 ether USD
//     // then alice borrowing power = 80 * 0.8 * 9000 / 10000 = 57.6 ether USD

//     mockOracle.setTokenPrice(address(weth), 8e17);

//     // add time 1 day
//     // 0.00016921837224 is interest rate per day of (30% condition slope)
//     // 0.0002820306204288 is interest rate per day of (50% condition slope)
//     // then total debt value of usdc should increase by 0.00016921837224 * 30 = 0.005076
//     // then total debt value of btc should increase by 0.0002820306204288 * 5 = 0.001410153102144
//     vm.warp(block.timestamp + 1 days);

//     // set price to weth from 1 to 0.8 ether USD
//     // then alice borrowing power = 40 * 0.8 * 9000 / 10000 = 28.8 ether USD

//     mockOracle.setTokenPrice(address(weth), 8e17);
//     mockOracle.setTokenPrice(address(usdc), 1 ether);
//     mockOracle.setTokenPrice(address(btc), 10e18);

//     // bob try repurchase with 40 usdc
//     // eth price = 0.8 USD
//     // usdc price = 1 USD
//     // reward = 0.01%
//     // repurchase fee = 1%
//     // timestamp increased by 1 day, usdc debt value should increased to 30.005076
//     // timestamp increased by 1 day, btc value should increased to 5.001410153102144
//     vm.prank(BOB, BOB);
//     liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, normalizeEther(40 ether, usdcDecimal));

//     // alice just have usdc debt 30.005076 (with interest)
//     // when repay amount (40) > _debtValue + fee (30.005076 + 0.300050) = 30.305126
//     // then actual repay amount should be 30.305126
//     // repay value = 30.305126 * 1 = 30.305126 USD
//     // with reward amount = 30.305126 * 1.01 = 30.60817726 USD
//     // converted weth amount = 30.60817726 / 0.8 = 38.260221575
//     // fee amount = 30.005076 * 0.01 = 0.300050
//     uint256 _expectedFee = normalizeEther(0.300050 ether, usdcDecimal);
//     uint256 _bobUsdcBalanceAfter = usdc.balanceOf(BOB);
//     uint256 _bobWethBalanceAfter = weth.balanceOf(BOB);

//     // check bob balance
//     assertEq(_bobUsdcBalanceBefore - _bobUsdcBalanceAfter, normalizeEther(30.305126 ether, usdcDecimal)); // pay 30.305126
//     assertEq(_bobWethBalanceAfter - _bobWethBalanceBefore, normalizeEther(38.260221575 ether, wethDecimal)); // get 38.260221575 weth

//     CacheState memory _stateAfter = CacheState({
//       collat: viewFacet.getTotalCollat(_collatToken),
//       subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, _collatToken),
//       debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
//       debtValue: viewFacet.getOverCollatTokenDebtValue(_debtToken),
//       subAccountDebtShare: 0
//     });
//     (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, _debtToken);

//     // check state
//     // note: before repurchase state should be like these
//     // collat amount should be = 100 on weth
//     // collat debt value should be | usdc: 30.005076 | btc: 5.001410153102144 | after accure interest
//     // collat debt share should be | usdc: 30 | btc: 5 |
//     // then after repurchase
//     // collat amount should be = 100 - (_collatAmountOut) = 100 - 38.260221575 = 61.739778425
//     // actual repaid debt amount = (_repayAmount - fee) = 30.305126 - 0.300050 = 30.005076
//     // collat debt value should be = 30.005076 - (actual repaid debt amount) = 30.005076 - 30.005076 = 0
//     // _repayShare = actual repaid debt amount * totalDebtShare / totalDebtValue = 30.005076 * 30 / 30.005076 = 30
//     // collat debt share should be = 30 - (_repayShare) = 30 - 30 = 0
//     assertEq(_stateAfter.collat, normalizeEther(61.739778425 ether, wethDecimal));
//     assertEq(_stateAfter.subAccountCollat, normalizeEther(61.739778425 ether, wethDecimal));
//     assertEq(_stateAfter.debtValue, 0);
//     assertEq(_stateAfter.debtShare, 0);
//     assertEq(_stateAfter.subAccountDebtShare, 0);

//     // check state for btc should not be changed
//     CacheState memory _btcState = CacheState({
//       collat: viewFacet.getTotalCollat(address(btc)),
//       subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, address(btc)),
//       debtShare: viewFacet.getOverCollatTokenDebtShares(address(btc)),
//       debtValue: viewFacet.getOverCollatTokenDebtValue(address(btc)),
//       subAccountDebtShare: 0
//     });
//     (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, address(btc));
//     assertEq(_btcState.collat, 0);
//     assertEq(_btcState.subAccountCollat, 0);
//     assertEq(_btcState.debtValue, normalizeEther(5.001410153102144 ether, btcDecimal));
//     assertEq(_btcState.debtShare, normalizeEther(5 ether, btcDecimal));

//     assertEq(MockERC20(_debtToken).balanceOf(liquidationTreasury) - _treasuryFeeBefore, _expectedFee);

//     // debt token in MiniFL should be equal to debtShare after repurchased (withdrawn & burned)
//     // since debt token is minted only one time, so the totalSupply should be equal to _stateAfter.debtShare after burned
//     address _miniFLDebtToken = viewFacet.getDebtTokenFromToken(_debtToken);
//     uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(_miniFLDebtToken);
//     assertEq(_miniFL.getUserTotalAmountOf(_poolId, ALICE), _stateAfter.debtShare);
//     assertEq(DebtToken(_miniFLDebtToken).totalSupply(), _stateAfter.debtShare);
//   }

//   function testRevert_ShouldRevertIfSubAccountIsHealthy() external {
//     // criteria
//     address _debtToken = address(usdc);
//     address _collatToken = address(weth);

//     address[] memory repurchaserOk = new address[](1);
//     repurchaserOk[0] = BOB;

//     adminFacet.setRepurchasersOk(repurchaserOk, true);

//     vm.prank(BOB);
//     vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Healthy.selector));
//     // bob try repurchase with 2 usdc
//     liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, normalizeEther(2 ether, usdcDecimal));

//     // case borrowingPower == usedBorrowingPower
//     // borrow more to increase usedBorrowingPower to be equal to totalBorrowingPower
//     // ALICE borrow 32.4 usdc convert to usedBorrowingPower = 32.4 * 10000 / 9000 = 36 USD
//     vm.prank(ALICE);
//     accountManager.borrow(0, address(usdc), normalizeEther(2.4 ether, usdcDecimal));

//     vm.prank(BOB);
//     vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Healthy.selector));
//     liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, normalizeEther(2 ether, usdcDecimal));
//   }

//   function testRevert_ShouldRevertRepurchaserIsNotOK() external {
//     // criteria
//     address _debtToken = address(usdc);
//     address _collatToken = address(weth);

//     vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Unauthorized.selector));
//     // bob try repurchase with 2 usdc
//     liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, normalizeEther(2 ether, usdcDecimal));
//   }

//   function testRevert_shouldRevertIfRepayIsTooHigh() external {
//     // criteria
//     address _debtToken = address(usdc);
//     address _collatToken = address(weth);

//     // collat amount should be = 40
//     // collat debt value should be = 30
//     // collat debt share should be = 30
//     CacheState memory _stateBefore = CacheState({
//       collat: viewFacet.getTotalCollat(_collatToken),
//       subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, _collatToken),
//       debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
//       debtValue: viewFacet.getOverCollatTokenDebtValue(_debtToken),
//       subAccountDebtShare: 0
//     });
//     (_stateBefore.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, _debtToken);

//     // add time 1 day
//     // then total debt value should increase by 0.00016921837224 * 30 = 0.0050765511672
//     vm.warp(block.timestamp + 1 days + 1);

//     // set price to weth from 1 to 0.8 ether USD
//     // then alice borrowing power = 40 * 0.8 * 9000 / 10000 = 28.8 ether USD

//     mockOracle.setTokenPrice(address(weth), 8e17);
//     mockOracle.setTokenPrice(address(usdc), 1 ether);
//     mockOracle.setTokenPrice(address(btc), 10e18);

//     // bob try repurchase with 2 usdc
//     // eth price = 0.8 USD
//     // usdc price = 1 USD
//     // reward = 0.01%
//     // timestamp increased by 1 day, debt value should increased to 30.0050765511672
//     vm.startPrank(BOB, BOB);
//     vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_RepayAmountExceedThreshold.selector));
//     // bob try repurchase with 20 usdc but borrowed value is 30.0050765511672 / 2 = 15.0025382755836,
//     // so bob can't pay more than 15.0025382755836 followed by condition (!> 50% of borrowed value)
//     liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, normalizeEther(20 ether, usdcDecimal));
//     vm.stopPrank();
//   }

//   function testRevert_ShouldRevertIfInsufficientCollateralAmount() external {
//     vm.startPrank(ALICE);
//     // alice has 36 ether USD power from eth
//     // alice add more collateral in other assets
//     // then borrowing power will be increased by 100 * 10 * 9000 / 10000 = 900 ether USD
//     // total borrowing power is 936 ether USD
//     accountManager.addCollateralFor(ALICE, 0, address(btc), normalizeEther(100 ether, btcDecimal));
//     // alice borrow more usdc token more 50% of vault = 50 usdc
//     // alice used borrowed value is ~80
//     accountManager.borrow(0, address(usdc), normalizeEther(50 ether, usdcDecimal));
//     vm.stopPrank();

//     // criteria
//     address _debtToken = address(usdc);
//     address _collatToken = address(weth);

//     // add time 1 day
//     // 0.0004512489926688 is interest rate per day of (80% condition slope)
//     // then total debt value of usdc should increase by 0.0004512489926688 * 80 = 0.036099919413504
//     vm.warp(block.timestamp + 1 days + 1);

//     // set price to btc from 10 to 0.1 ether USD
//     // then alice borrowing power from btc = 100 * 0.1 * 9000 / 10000 = 9 ether USD
//     // total borrowing power is 36 + 9 = 45 ether USD
//     mockOracle.setTokenPrice(address(btc), normalizeEther(1e17, usdDecimal));
//     mockOracle.setTokenPrice(address(weth), normalizeEther(1e18, usdDecimal));
//     mockOracle.setTokenPrice(address(usdc), normalizeEther(1e18, usdDecimal));

//     // bob try repurchase with 40 usdc
//     // eth price = 0.2 USD
//     // usdc price = 1 USD
//     // reward = 0.01%
//     // timestamp increased by 1 day, usdc debt value should increased to 80.036099919413504
//     vm.startPrank(BOB, BOB);

//     // repay value = 40 * 1 = 40 USD
//     // reward amount = 40 * 1.01 = 40.40 USD
//     // converted weth amount = 40.40 / 1 = 40.40
//     // should revert because alice has eth collat just 40
//     vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_InsufficientAmount.selector));
//     liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, normalizeEther(40 ether, usdcDecimal));
//     vm.stopPrank();
//   }

//   function testCorrectness_WhenRepurchaseWithRepayTokenAndCollatTokenAreSameToken_TransferTokenCorrectly() external {
//     vm.startPrank(ALICE);
//     accountManager.addCollateralFor(ALICE, 0, address(usdc), normalizeEther(20 ether, usdcDecimal));

//     accountManager.borrow(0, address(usdc), normalizeEther(10 ether, usdcDecimal));
//     // Now!!, alice borrowed 40% of vault then interest be 0.082352941146288000 per year
//     // interest per day ~ 0.000225624496291200
//     vm.stopPrank();

//     // criteria
//     address _debtToken = address(usdc);
//     address _collatToken = address(usdc);

//     uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);

//     // collat (weth) amount should be = 40
//     // collat (usdc) amount should be = 20
//     // collat debt value should be = 40
//     // collat debt share should be = 40
//     CacheState memory _stateBefore = CacheState({
//       collat: viewFacet.getTotalCollat(_collatToken),
//       subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, _collatToken),
//       debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
//       debtValue: viewFacet.getOverCollatTokenDebtValue(_debtToken),
//       subAccountDebtShare: 0
//     });
//     (_stateBefore.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, _debtToken);

//     uint256 _treasuryFeeBefore = MockERC20(_debtToken).balanceOf(liquidationTreasury);

//     // add time 1 day
//     // then total debt value should increase by 0.000225624496291200 * 40 = 0.009024979851648
//     vm.warp(block.timestamp + 1 days);

//     // set price to weth from 1 to 0.6 ether USD
//     // then alice borrowing power (weth) = 40 * 0.6 * 9000 / 10000 = 21.6 ether USD
//     // then alice borrowing power (usdc) = 20 * 1 * 9000 / 10000 = 18 ether USD
//     // total = 28.8 + 18 = 46.8 ether USD
//     mockOracle.setTokenPrice(address(usdc), normalizeEther(1 ether, usdDecimal));
//     mockOracle.setTokenPrice(address(weth), normalizeEther(6e17, usdDecimal));
//     mockOracle.setTokenPrice(address(btc), normalizeEther(10 ether, usdDecimal));

//     // bob try repurchase with 15 usdc
//     // eth price = 0.6 USD
//     // usdc price = 1 USD
//     // reward = 1%
//     // repurchase fee = 1%
//     // timestamp increased by 1 day, debt value should increased to 30.009024979851648
//     // repaid = desired / (1 + feePct) = 15 / (1 + 0.01) = 14.85[1485]...
//     // fee amount = desired - repaid = 15 - 14.85[1485]... = 0.1485[1485]... ~ 0.148515 usdc
//     uint256 _expectedFee = normalizeEther(0.148515 ether, usdcDecimal);
//     vm.prank(BOB, BOB);
//     liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, normalizeEther(15 ether, usdcDecimal));

//     // repay value = 15 * 1 = 1 USD
//     // reward amount = 15 * 1.01 = 15.15 USD
//     // converted usdc amount = 15.15 / 1 = 15.15 ether

//     uint256 _bobUsdcBalanceAfter = usdc.balanceOf(BOB);

//     // check bob balance
//     // pay 15 usdc and get reward 15.15 usdc net increase 0.15 usdc
//     assertEq(_bobUsdcBalanceAfter - _bobUsdcBalanceBefore, normalizeEther(0.15 ether, usdcDecimal));

//     CacheState memory _stateAfter = CacheState({
//       collat: viewFacet.getTotalCollat(_collatToken),
//       subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, _collatToken),
//       debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
//       debtValue: viewFacet.getOverCollatTokenDebtValue(_debtToken),
//       subAccountDebtShare: 0
//     });
//     (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, _debtToken);

//     // check state
//     // note: before repurchase state should be like these
//     // collat amount (usdc) should be = 20
//     // collat debt value should be = 40.009024 (0.009024979851648 is fixed interest increased)
//     // collat debt share should be = 40
//     // then after repurchase
//     // collat amount should be = 20 - (_collatAmountOut) = 20 - 15.15 = 4.85
//     // actual repaid debt amount = 15 / (1 + 0.01)
//     // collat debt value should be = 40.009024 - (actual repaid debt amount) = 40.009024 - (15 / (1 + 0.01)) = 25.157539
//     // _repayShare = actual repaid debt amount * totalDebtShare / totalDebtValue = 15 / (1 + 0.01) * 40 / 40.009024
//     // collat debt share should be = 40 - (_repayShare) = 40 - (15 / (1 + 0.01) * 40 / 40.009024) = 25.151865
//     assertEq(_stateAfter.collat, normalizeEther(4.85 ether, usdcDecimal));
//     assertEq(_stateAfter.subAccountCollat, normalizeEther(4.85 ether, usdcDecimal));
//     assertEq(_stateAfter.debtValue, normalizeEther(25.157539 ether, usdcDecimal));
//     assertEq(_stateAfter.debtShare, normalizeEther(25.151865 ether, usdcDecimal));
//     assertEq(_stateAfter.subAccountDebtShare, normalizeEther(25.151865 ether, usdcDecimal));
//     // globalDebt should equal to debtValue since there is only 1 position
//     assertEq(viewFacet.getGlobalDebtValue(_debtToken), normalizeEther(25.157539 ether, usdcDecimal));

//     assertEq(MockERC20(_debtToken).balanceOf(liquidationTreasury) - _treasuryFeeBefore, _expectedFee);

//     // debt token in MiniFL should be equal to debtShare after repurchased (withdrawn & burned)
//     // since debt token is minted only one time, so the totalSupply should be equal to _stateAfter.debtShare after burned
//     address _miniFLDebtToken = viewFacet.getDebtTokenFromToken(_debtToken);
//     uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(_miniFLDebtToken);
//     assertEq(_miniFL.getUserTotalAmountOf(_poolId, ALICE), _stateAfter.debtShare);
//     assertEq(DebtToken(_miniFLDebtToken).totalSupply(), _stateAfter.debtShare);
//   }
// }
