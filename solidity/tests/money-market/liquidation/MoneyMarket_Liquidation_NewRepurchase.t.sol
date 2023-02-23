// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, DebtToken, console } from "../MoneyMarket_BaseTest.t.sol";
import "solidity/tests/utils/StdUtils.sol";
import "solidity/tests/utils/StdAssertions.sol";

// libs
import { LibMoneyMarket01 } from "../../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { IBorrowFacet, LibDoublyLinkedList } from "../../../contracts/money-market/facets/BorrowFacet.sol";
import { ILiquidationFacet } from "../../../contracts/money-market/facets/LiquidationFacet.sol";
import { IAdminFacet } from "../../../contracts/money-market/facets/AdminFacet.sol";
import { TripleSlopeModel6, IInterestRateModel } from "../../../contracts/money-market/interest-models/TripleSlopeModel6.sol";
import { FixedFeeModel, IFeeModel } from "../../../contracts/money-market/fee-models/FixedFeeModel.sol";
import { IMiniFL } from "../../../contracts/money-market/interfaces/IMiniFL.sol";
import { IERC20 } from "solidity/contracts/money-market/interfaces/IERC20.sol";

contract MoneyMarket_Liquidation_NewRepurchaseTest is MoneyMarket_BaseTest, StdUtils, StdAssertions {
  function setUp() public override {
    super.setUp();

    /**
     * setup
     *  - initial prices: 1 weth = 1 usd, 1 usdc = 1 usd
     *  - all token have collatFactor 9000, borrowFactor 9000
     *  - 10% fee, 1% reward
     *  - allow to repurchase up to 100% of position
     *  - no interest
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

    // seed money market
    vm.startPrank(BOB);
    accountManager.deposit(address(usdc), normalizeEther(1000 ether, usdcDecimal));
    accountManager.deposit(address(btc), normalizeEther(100 ether, btcDecimal));
    accountManager.deposit(address(weth), normalizeEther(100 ether, wethDecimal));
    vm.stopPrank();
  }

  struct TestRepurchaseParams {
    address borrower;
    address repurchaser;
    address collatToken;
    address debtToken;
    uint256 desiredRepayAmount;
    uint256 repurchaseFeeBps;
    uint256 collatTokenPrice;
    uint256 debtTokenPriceDuringRepurchase;
    uint256 initialDebtAmount;
    uint256 initialCollateralAmount;
    uint256 repurchaserDebtTokenBalanceBefore;
    uint256 repurchaserCollatTokenBalanceBefore;
    uint256 treasuryDebtTokenBalanceBefore;
  }

  function _testRepurchase(TestRepurchaseParams memory params) internal {
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
    params.repurchaserDebtTokenBalanceBefore = weth.balanceOf(params.repurchaser);
    params.repurchaserCollatTokenBalanceBefore = usdc.balanceOf(params.repurchaser);
    params.treasuryDebtTokenBalanceBefore = weth.balanceOf(liquidationTreasury);
    params.initialCollateralAmount = viewFacet.getCollatAmountOf(params.borrower, subAccount0, params.collatToken);
    (, params.initialDebtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(
      params.borrower,
      subAccount0,
      params.debtToken
    );

    // ghost variables calculation
    uint256 _maxAmountRepurchasable = (params.initialDebtAmount * (10000 + params.repurchaseFeeBps)) / 10000;
    uint256 _repayAmountWithFee;
    uint256 _repayAmountWithoutFee;
    // case 1
    if (params.desiredRepayAmount > _maxAmountRepurchasable) {
      _repayAmountWithFee = _maxAmountRepurchasable;
      _repayAmountWithoutFee = params.initialDebtAmount;
    } else {
      // case 2
      _repayAmountWithFee = params.desiredRepayAmount;
      _repayAmountWithoutFee = (params.desiredRepayAmount * 10000) / (10000 + (params.repurchaseFeeBps));
    }
    uint256 _repurchaseFee = _repayAmountWithFee - _repayAmountWithoutFee;

    // constant 1% premium
    uint256 _repayTokenPriceWithPremium = (params.debtTokenPriceDuringRepurchase * (10000 + 100)) / 10000;
    uint256 _collatSold = (_repayAmountWithFee * _repayTokenPriceWithPremium) / params.collatTokenPrice;

    vm.prank(params.repurchaser);
    liquidationFacet.repurchase(
      params.borrower,
      subAccount0,
      params.debtToken,
      params.collatToken,
      params.desiredRepayAmount
    );

    /**
     * borrower final state
     *  - collateral = initial - collatSold
     *  - debt = initial - repayAmountWithoutFee
     */
    assertEq(
      viewFacet.getCollatAmountOf(params.borrower, subAccount0, params.collatToken),
      params.initialCollateralAmount - normalizeEther(_collatSold, IERC20(params.collatToken).decimals()),
      "borrower remaining collat"
    );
    (, uint256 _debtAmountAfter) = viewFacet.getOverCollatDebtShareAndAmountOf(
      params.borrower,
      subAccount0,
      params.debtToken
    );
    assertEq(
      _debtAmountAfter,
      params.initialDebtAmount - normalizeEther(_repayAmountWithoutFee, IERC20(params.debtToken).decimals()),
      "borrower remaining debt"
    );

    /**
     * repurchaser final state
     *  - collateral = initial + payout
     *  - debt = initial - repaid
     */
    assertEq(
      IERC20(params.collatToken).balanceOf(params.repurchaser),
      params.repurchaserCollatTokenBalanceBefore + normalizeEther(_collatSold, usdcDecimal),
      "repurchaser collatToken received"
    );
    assertEq(
      IERC20(params.debtToken).balanceOf(params.repurchaser),
      params.repurchaserDebtTokenBalanceBefore - _repayAmountWithFee,
      "repurchaser debtToken paid"
    );

    // check fee in debtToken to liquidationTreasury
    assertEq(
      IERC20(params.debtToken).balanceOf(liquidationTreasury),
      params.treasuryDebtTokenBalanceBefore + _repurchaseFee,
      "repurchase fee"
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

    TestRepurchaseParams memory params;
    params.borrower = ALICE;
    params.repurchaser = BOB;
    params.collatToken = address(usdc);
    params.debtToken = address(weth);
    params.desiredRepayAmount = _desiredRepayAmount;
    params.initialDebtAmount = _initialDebtAmount;
    params.initialCollateralAmount = _initialCollateralAmount;
    params.repurchaseFeeBps = 1000;
    params.collatTokenPrice = 1 ether;
    params.debtTokenPriceDuringRepurchase = 2 ether;
    _testRepurchase(params);
  }

  function testFuzz_ConsecutiveRepurchase(uint256[3] memory desiredRepayAmounts) public {
    // bound input to small amount to partially repurchase while
    // not making position healthy to allow final full repurchase
    for (uint256 i; i < desiredRepayAmounts.length; ++i) {
      desiredRepayAmounts[i] = bound(desiredRepayAmounts[i], 0, 0.05 ether);
    }

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

    TestRepurchaseParams memory params;
    params.borrower = ALICE;
    params.repurchaser = BOB;
    params.collatToken = address(usdc);
    params.debtToken = address(weth);
    params.repurchaseFeeBps = 1000;
    params.collatTokenPrice = 1 ether;
    params.debtTokenPriceDuringRepurchase = 2 ether;

    uint256 _treasuryBalanceBefore = weth.balanceOf(liquidationTreasury);

    // partially repurchase 3 times
    // followed by full repurchase to clear all debt
    for (uint256 i; i < desiredRepayAmounts.length; ++i) {
      params.desiredRepayAmount = desiredRepayAmounts[i];
      _testRepurchase(params);
    }
    params.desiredRepayAmount = type(uint256).max;
    _testRepurchase(params);

    // expect no debt remain
    (, uint256 _debtAmountAfter) = viewFacet.getOverCollatDebtShareAndAmountOf(
      params.borrower,
      subAccount0,
      params.debtToken
    );
    assertEq(_debtAmountAfter, 0, "borrower final debt");

    // expect total repurchase fee = max fee
    uint256 _maxFee = 0.1 ether;
    assertApproxEqAbs(weth.balanceOf(liquidationTreasury), _treasuryBalanceBefore + _maxFee, 3, "max fee");
  }
}
