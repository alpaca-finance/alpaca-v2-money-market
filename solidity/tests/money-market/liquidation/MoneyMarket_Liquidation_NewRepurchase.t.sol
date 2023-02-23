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

    /**
     * BOB repurchase
     *  - currentDebt = 1 weth
     *  - maxAmountRepurchaseable = currentDebt * (1 + feePct)
     *                            = 1 * (1 + 0.1) = 1.1 weth
     *  - fee = repayAmountWithFee - repayAmountWithoutFee
     *  - repayTokenPriceWithPremium = repayTokenPrice * (1 + rewardPct)
     *                               = 2 * (1 + 0.01) = 2.02 usd
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
    uint256 _bobWethBalanceBefore = weth.balanceOf(BOB);
    uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);

    vm.prank(BOB);
    liquidationFacet.repurchase(ALICE, subAccount0, address(weth), address(usdc), _desiredRepayAmount);

    uint256 _maxAmountRepurchasable = 1.1 ether;
    uint256 _repayAmountWithFee;
    uint256 _repayAmountWithoutFee;
    // case 1
    if (_desiredRepayAmount > _maxAmountRepurchasable) {
      _repayAmountWithFee = _maxAmountRepurchasable;
      _repayAmountWithoutFee = _initialDebtAmount;
    } else {
      // case 2
      _repayAmountWithFee = _desiredRepayAmount;
      _repayAmountWithoutFee = (_desiredRepayAmount * 100) / (110);
    }

    uint256 _repayTokenPriceWithPremium = 2.02 ether;
    uint256 _collatTokenPrice = 1 ether;
    uint256 _collatSold = (_repayAmountWithFee * _repayTokenPriceWithPremium) / _collatTokenPrice;

    /**
     * ALICE final state
     *  - collateral = initial - sold
     *  - debt = initial - repayAmountWithoutFee
     */
    assertEq(
      viewFacet.getCollatAmountOf(ALICE, subAccount0, address(usdc)),
      normalizeEther(_initialCollateralAmount, usdcDecimal) - normalizeEther(_collatSold, usdcDecimal),
      "usdc collat"
    );
    (, uint256 _debtAmountAfter) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, subAccount0, address(weth));
    assertEq(_debtAmountAfter, _initialDebtAmount - _repayAmountWithoutFee, "weth debt");

    /**
     * BOB final state
     *  - weth = initial - repaid
     *  - usdc = initial + collat + reward
     */
    assertEq(weth.balanceOf(BOB), _bobWethBalanceBefore - _repayAmountWithFee, "weth paid");
    assertEq(usdc.balanceOf(BOB), _bobUsdcBalanceBefore + normalizeEther(_collatSold, usdcDecimal), "usdc received");
  }
}
