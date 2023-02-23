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

    // hard-coded repurchase reward = 1%
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
    uint256 repurchaserCollatTokenBalanceBefore;
    uint256 repurchaserDebtTokenBalanceBefore;
    uint256 initialDebtAmount;
    uint256 initialCollateralAmount;
    uint256 repurchaseFeeBps;
    uint256 collatTokenPrice;
    uint256 debtTokenPriceDuringRepurchase;
  }

  function _testRepurchase(TestRepurchaseParams memory vars) internal {
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
    vars.repurchaserDebtTokenBalanceBefore = weth.balanceOf(vars.repurchaser);
    vars.repurchaserCollatTokenBalanceBefore = usdc.balanceOf(vars.repurchaser);

    vm.prank(vars.repurchaser);
    liquidationFacet.repurchase(vars.borrower, subAccount0, vars.debtToken, vars.collatToken, vars.desiredRepayAmount);

    uint256 _maxAmountRepurchasable = (vars.initialDebtAmount * (10000 + vars.repurchaseFeeBps)) / 10000;
    uint256 _repayAmountWithFee;
    uint256 _repayAmountWithoutFee;
    // case 1
    if (vars.desiredRepayAmount > _maxAmountRepurchasable) {
      _repayAmountWithFee = _maxAmountRepurchasable;
      _repayAmountWithoutFee = vars.initialDebtAmount;
    } else {
      // case 2
      _repayAmountWithFee = vars.desiredRepayAmount;
      _repayAmountWithoutFee = (vars.desiredRepayAmount * 10000) / (10000 + (vars.repurchaseFeeBps));
    }

    // constant 1% premium
    uint256 _repayTokenPriceWithPremium = (vars.debtTokenPriceDuringRepurchase * (10000 + 100)) / 10000;
    uint256 _collatSold = (_repayAmountWithFee * _repayTokenPriceWithPremium) / vars.collatTokenPrice;

    /**
     * borrower final state
     *  - collateral = initial - collatSold
     *  - debt = initial - repayAmountWithoutFee
     */
    assertEq(
      viewFacet.getCollatAmountOf(vars.borrower, subAccount0, vars.collatToken),
      normalizeEther(vars.initialCollateralAmount, IERC20(vars.collatToken).decimals()) -
        normalizeEther(_collatSold, IERC20(vars.collatToken).decimals()),
      "borrower remaining collat"
    );
    (, uint256 _debtAmountAfter) = viewFacet.getOverCollatDebtShareAndAmountOf(
      vars.borrower,
      subAccount0,
      vars.debtToken
    );
    console.log(vars.initialDebtAmount);
    console.log(normalizeEther(vars.initialDebtAmount, IERC20(vars.debtToken).decimals()));
    console.log(_repayAmountWithoutFee);
    console.log(normalizeEther(_repayAmountWithoutFee, IERC20(vars.debtToken).decimals()));
    console.log(vars.initialDebtAmount - _repayAmountWithoutFee);
    console.log(
      normalizeEther(vars.initialDebtAmount, IERC20(vars.debtToken).decimals()) -
        normalizeEther(_repayAmountWithoutFee, IERC20(vars.debtToken).decimals())
    );
    assertEq(
      _debtAmountAfter,
      normalizeEther(vars.initialDebtAmount, IERC20(vars.debtToken).decimals()) -
        normalizeEther(_repayAmountWithoutFee, IERC20(vars.debtToken).decimals()),
      "borrower remaining debt"
    );

    /**
     * repurchaser final state
     *  - collateral = initial + payout
     *  - debt = initial - repaid
     */
    assertEq(
      IERC20(vars.collatToken).balanceOf(vars.repurchaser),
      vars.repurchaserCollatTokenBalanceBefore + normalizeEther(_collatSold, usdcDecimal),
      "repurchaser collatToken received"
    );
    assertEq(
      IERC20(vars.debtToken).balanceOf(vars.repurchaser),
      vars.repurchaserDebtTokenBalanceBefore - _repayAmountWithFee,
      "repurchaser debtToken paid"
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

    TestRepurchaseParams memory vars;
    vars.borrower = ALICE;
    vars.repurchaser = BOB;
    vars.collatToken = address(usdc);
    vars.debtToken = address(weth);
    vars.desiredRepayAmount = _desiredRepayAmount;
    vars.initialDebtAmount = _initialDebtAmount;
    vars.initialCollateralAmount = _initialCollateralAmount;
    vars.repurchaseFeeBps = 1000;
    vars.collatTokenPrice = 1 ether;
    vars.debtTokenPriceDuringRepurchase = 2 ether;
    _testRepurchase(vars);
  }
}
