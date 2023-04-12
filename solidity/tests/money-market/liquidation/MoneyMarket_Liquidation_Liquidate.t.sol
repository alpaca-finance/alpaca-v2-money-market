// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest, MockERC20, DebtToken, console } from "../MoneyMarket_BaseTest.t.sol";

// interfaces
import { ILiquidationFacet } from "../../../contracts/money-market/interfaces/ILiquidationFacet.sol";
import { TripleSlopeModel6, IInterestRateModel } from "../../../contracts/money-market/interest-models/TripleSlopeModel6.sol";
import { IMiniFL } from "../../../contracts/money-market/interfaces/IMiniFL.sol";

// mocks
import { MockLiquidationStrategy } from "../../mocks/MockLiquidationStrategy.sol";
import { MockBadLiquidationStrategy } from "../../mocks/MockBadLiquidationStrategy.sol";

struct CacheState {
  uint256 collat;
  uint256 subAccountCollat;
  uint256 debtShare;
  uint256 debtValue;
  uint256 subAccountDebtShare;
}

contract MoneyMarket_Liquidation_LiquidateTest is MoneyMarket_BaseTest {
  uint256 _subAccountId = 0;
  address _aliceSubAccount0 = address(uint160(ALICE) ^ uint160(_subAccountId));
  MockLiquidationStrategy internal mockLiquidationStrategy;
  MockBadLiquidationStrategy internal mockBadLiquidationStrategy;
  IMiniFL internal _miniFL;

  function setUp() public override {
    super.setUp();

    TripleSlopeModel6 tripleSlope6 = new TripleSlopeModel6();
    adminFacet.setInterestModel(address(weth), address(tripleSlope6));
    adminFacet.setInterestModel(address(btc), address(tripleSlope6));
    adminFacet.setInterestModel(address(usdc), address(tripleSlope6));

    // setup liquidationStrategy
    mockLiquidationStrategy = new MockLiquidationStrategy(address(mockOracle));
    usdc.mint(address(mockLiquidationStrategy), normalizeEther(1000 ether, usdcDecimal));
    mockBadLiquidationStrategy = new MockBadLiquidationStrategy();
    usdc.mint(address(mockBadLiquidationStrategy), normalizeEther(1000 ether, usdcDecimal));

    _miniFL = IMiniFL(address(miniFL));

    address[] memory _liquidationStrats = new address[](2);
    _liquidationStrats[0] = address(mockLiquidationStrategy);
    _liquidationStrats[1] = address(mockBadLiquidationStrategy);
    adminFacet.setLiquidationStratsOk(_liquidationStrats, true);

    address[] memory _liquidationCallers = new address[](1);
    _liquidationCallers[0] = liquidator;
    adminFacet.setLiquidatorsOk(_liquidationCallers, true);

    vm.startPrank(DEPLOYER);
    mockOracle.setTokenPrice(address(btc), normalizeEther(10 ether, btcDecimal));
    vm.stopPrank();

    // bob deposit 100 usdc and 10 btc
    vm.startPrank(BOB);
    accountManager.deposit(address(usdc), normalizeEther(100 ether, usdcDecimal));
    accountManager.deposit(address(btc), normalizeEther(10 ether, btcDecimal));
    vm.stopPrank();

    vm.startPrank(ALICE);
    accountManager.addCollateralFor(ALICE, 0, address(weth), normalizeEther(40 ether, wethDecimal));
    // alice added collat 40 ether
    // given collateralFactor = 9000, weth price = 1
    // then alice got power = 40 * 1 * 9000 / 10000 = 36 ether USD
    // alice borrowed 30% of vault then interest should be 0.0617647058676 per year
    // interest per day = 0.00016921837224
    accountManager.borrow(0, address(usdc), normalizeEther(30 ether, usdcDecimal));
    vm.stopPrank();
  }

  function testCorrectness_WhenLiquidateMoreThanDebt_ShouldLiquidateAllDebtOnThatToken() external {
    /**
     * scenario:
     *
     * 1. 1 usdc/weth, ALICE post 40 weth as collateral, borrow 30 usdc
     *    - ALICE borrowing power = 40 * 1 * 9000 / 10000 = 36 usd
     *
     * 2. 1 day passesd, debt accrued, weth price drops to 0.8 usdc/weth, position become liquidatable
     *    - usdc debt has increased to 30.005076 usdc
     *    - ALICE borrowing power = 40 * 0.8 * 9000 / 10000 = 28.8 usd
     *
     * 3. try to liquidate 40 usdc with weth collateral
     *
     * 4. should be able to liquidate with 30.005076 usdc repaid, 37.806395 weth reduced from collateral and 0.300050 usdc to treasury
     *    - remaining collateral = 40 - 37.8814075 = 2.193605 weth
     *      - totalLiquidationFee = 30.005076 * 1% = 0.30005 usdc is taken to treasury as liquidation fee
     *      - @0.8 usdc/weth 30.305126 usdc (with fee) = 37.8814075 weth is liquidated
     *      - total weth liquidated = 37.8814075 + 0.300050 = 37.806395
     *    - remaining debt value = 0
     *    - remaining debt share = 0
     */

    adminFacet.setLiquidationParams(10000, 11111); // allow liquidation of entire subAccount

    address _debtToken = address(usdc);
    address _collatToken = address(weth);

    vm.warp(block.timestamp + 1 days);

    // LiquidationFacet need these to function
    mockOracle.setTokenPrice(address(weth), 8e17);
    mockOracle.setTokenPrice(address(usdc), 1 ether);
    // MockLiquidationStrategy need these to function
    mockOracle.setTokenPrice(address(weth), 8e17);

    uint256 _treasuryBalanceBefore = MockERC20(_debtToken).balanceOf(liquidationTreasury);

    vm.prank(liquidator);
    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      _subAccountId,
      _debtToken,
      _collatToken,
      0
    );

    CacheState memory _stateAfter = CacheState({
      collat: viewFacet.getTotalCollat(_collatToken),
      subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatTokenDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, _debtToken);

    assertEq(_stateAfter.collat, normalizeEther(2.1185925 ether, wethDecimal)); // 40 - 37.88140914584859 = 2.11859085415141 weth remaining
    assertEq(_stateAfter.subAccountCollat, normalizeEther(2.1185925 ether, wethDecimal)); // same as collat
    // entire positon got liquidated, everything = 0
    assertEq(_stateAfter.debtValue, 0);
    assertEq(_stateAfter.debtShare, 0);
    assertEq(_stateAfter.subAccountDebtShare, 0);

    assertEq(
      MockERC20(_debtToken).balanceOf(liquidationTreasury) - _treasuryBalanceBefore,
      normalizeEther(0.30005 ether, usdcDecimal)
    );

    // debt token in MiniFL should be equal to debtShare after liquidated (withdrawn & burned)
    // since debt token is minted only one time, so the totalSupply should be equal to _stateAfter.debtShare after burned
    address _miniFLDebtToken = viewFacet.getDebtTokenFromToken(_debtToken);
    uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(_miniFLDebtToken);
    assertEq(_miniFL.getUserTotalAmountOf(_poolId, ALICE), _stateAfter.debtShare);
    assertEq(DebtToken(_miniFLDebtToken).totalSupply(), _stateAfter.debtShare);
  }

  function testCorrectness_WhenLiquidateAllCollateral_ShouldWorkButTreasuryReceiveNoFee() external {
    /**
     * scenario:
     *
     * 1. 1 usdc/weth, 10 usdc/btc, ALICE post 40 weth and 100 btc as collateral, borrow 80 usdc
     *    - borrowing power = 40 * 1 * 9000 / 10000 + 100 * 10 * 9000 / 10000 = 936 usd
     *
     * 2. 1 day passed, debt accrued, btc price drops to 0.1 usd/btc, position become liquidatable
     *    - usdc debt has increased to 80.036099 usdc
     *      - 0.0004512489926688 is interest rate per day of (80% condition slope)
     *      - total debt value of usdc should increase by 0.0004512489926688 * 80 = 0.036099
     *    - borrowing power = 40 * 1 * 9000 / 10000 + 100 * 0.1 * 9000 / 10000 = 45 usd
     *
     * 3. try to liquidate usdc debt with 40 weth
     *
     * 4. should be able to liquidate with 39.603960 usdc repaid and 40 weth liquidated
     *    - remaining collateral = 0 weth
     *      - @1 usdc/weth 39.6 usdc = 39.6 weth is liquidated
     *      - totalLiquidationFee = 39.603960 * 1% = 0.396039
     *    - remaining debt value = 80.036099 - 39.603960 = 40.432139 usdc
     *    - remaining debt share = 80 - 39.586097209550105281 = 40.413902 shares
     *      - repaid debt shares = amountRepaid * totalDebtShare / totalDebtValue = 39.6 * 80 / 80.036099 = 39.582138599829150270272757155067956377008065689156955144328424412...
     */

    vm.startPrank(ALICE);
    accountManager.addCollateralFor(ALICE, 0, address(btc), 100 ether);
    accountManager.borrow(0, address(usdc), normalizeEther(50 ether, usdcDecimal));
    vm.stopPrank();

    address _debtToken = address(usdc);
    address _collatToken = address(weth);

    vm.warp(block.timestamp + 1 days);

    mockOracle.setTokenPrice(address(btc), 1e17);
    mockOracle.setTokenPrice(address(weth), 1 ether);
    mockOracle.setTokenPrice(address(usdc), 1 ether);

    vm.prank(liquidator);
    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      _subAccountId,
      _debtToken,
      _collatToken,
      0
    );

    CacheState memory _stateAfter = CacheState({
      collat: viewFacet.getTotalCollat(_collatToken),
      subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatTokenDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, _debtToken);

    assertEq(_stateAfter.collat, 0);
    assertEq(_stateAfter.subAccountCollat, 0);
    assertEq(_stateAfter.debtValue, normalizeEther(40.432138 ether, usdcDecimal));
    assertEq(_stateAfter.debtShare, normalizeEther(40.413902 ether, usdcDecimal));
    assertEq(_stateAfter.subAccountDebtShare, normalizeEther(40.413902 ether, usdcDecimal));

    assertEq(MockERC20(_debtToken).balanceOf(liquidationTreasury), normalizeEther(0.396039 ether, usdcDecimal));

    // debt token in MiniFL should be equal to debtShare after liquidated (withdrawn & burned)
    // since debt token is minted only one time, so the totalSupply should be equal to _stateAfter.debtShare after burned
    address _miniFLDebtToken = viewFacet.getDebtTokenFromToken(_debtToken);
    uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(_miniFLDebtToken);
    assertEq(_miniFL.getUserTotalAmountOf(_poolId, ALICE), _stateAfter.debtShare);
    assertEq(DebtToken(_miniFLDebtToken).totalSupply(), _stateAfter.debtShare);
  }

  function testCorrectness_WhenLiquidationStrategyReturnRepayTokenLessThanExpected_AndNoCollatIsReturned_ShouldCauseBadDebt()
    external
  {
    adminFacet.setLiquidationParams(10000, 11111); // allow liquidation of entire subAccount

    address _debtToken = address(usdc);
    address _collatToken = address(weth);

    vm.warp(block.timestamp + 1 days);

    // LiquidationFacet need these to function
    mockOracle.setTokenPrice(address(weth), 8e17);
    mockOracle.setTokenPrice(address(usdc), 1 ether);

    uint256 _treasuryBalanceBefore = MockERC20(_debtToken).balanceOf(liquidationTreasury);

    // return non, all debt is bad debt
    mockBadLiquidationStrategy.setReturnRepayAmount(normalizeEther(0 ether, usdcDecimal));
    vm.prank(liquidator);
    liquidationFacet.liquidationCall(
      address(mockBadLiquidationStrategy), // this strategy always return repayToken as set prior
      ALICE,
      _subAccountId,
      _debtToken,
      _collatToken,
      0
    );

    CacheState memory _stateAfter = CacheState({
      collat: viewFacet.getTotalCollat(_collatToken),
      subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatTokenDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, _debtToken);

    // strategy doesn't return collat
    assertEq(_stateAfter.collat, 0);
    assertEq(_stateAfter.subAccountCollat, 0);
    // bad debt (0 collat with remaining debt)
    // since liquidation will write off whole subaccount
    // debt should be 0
    assertEq(_stateAfter.debtValue, normalizeEther(0, usdcDecimal));
    assertEq(_stateAfter.debtShare, normalizeEther(0, usdcDecimal));
    assertEq(_stateAfter.subAccountDebtShare, normalizeEther(0, usdcDecimal));

    // total token should decrease due to the fact that bad debt was booked
    assertEq(viewFacet.getGlobalDebtValue(_debtToken), 0);

    assertEq(viewFacet.getTotalToken(_debtToken), normalizeEther(70 ether, usdcDecimal)); // 30 usdc bad debt
    assertEq(viewFacet.getFloatingBalance(_debtToken), normalizeEther(70 ether, usdcDecimal)); // since debt went to 0, reserve only has 70 left
    (uint256 _totalUsedBorrowingPower, ) = viewFacet.getTotalUsedBorrowingPower(ALICE, _subAccountId);
    assertEq(_totalUsedBorrowingPower, 0);
    // assertEq(viewFacet.getTotalUsedBorrowingPower(ALICE, _subAccountId), 0);
    // check liquidation fee funds flow
    // there's no liquidation fee due to the fact that the strat return nothing
    assertEq(
      MockERC20(_debtToken).balanceOf(liquidationTreasury) - _treasuryBalanceBefore,
      normalizeEther(0 ether, usdcDecimal)
    );

    // debt token in MiniFL should be equal to debtShare after liquidated (withdrawn & burned)
    // since debt token is minted only one time, so the totalSupply should be equal to _stateAfter.debtShare after burned
    address _miniFLDebtToken = viewFacet.getDebtTokenFromToken(_debtToken);
    uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(_miniFLDebtToken);
    assertEq(_miniFL.getUserTotalAmountOf(_poolId, ALICE), _stateAfter.debtShare);
    assertEq(DebtToken(_miniFLDebtToken).totalSupply(), _stateAfter.debtShare);
  }

  function testRevert_WhenLiquidateWhileSubAccountIsHealthy() external {
    vm.prank(liquidator);
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Healthy.selector));
    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      _subAccountId,
      address(usdc),
      address(weth),
      0
    );

    // case borrowingPower == usedBorrowingPower * threshold
    vm.prank(ALICE);

    // note: have to borrow and lower price because doing just either borrow or increase price
    // won't be able to make both side equal

    // if we only set weth price to 0.8333..
    // there will be precision loss that make it impossible for both side to be equal
    // if we only borrow more it will hit borrow limit before reach equality

    // try to make usedBorrowingPower / borrowingPower = threshold
    // borrow more to increase usedBorrowingPower to 36 ether
    accountManager.borrow(0, address(usdc), normalizeEther(2.4 ether, usdcDecimal));

    // decrease price to lower borrowingPower so that 36 / (40 * Price * 0.9) = 1.1111
    // Price = 0.900009
    // add a little bit so it can't be liquidate
    mockOracle.setTokenPrice(address(weth), 0.9000091 ether);

    vm.prank(liquidator);
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Healthy.selector));
    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      _subAccountId,
      address(usdc),
      address(weth),
      0
    );
  }

  function testRevert_WhenLiquidationStrategyIsNotOk() external {
    vm.prank(liquidator);
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Unauthorized.selector));
    liquidationFacet.liquidationCall(address(0), ALICE, _subAccountId, address(usdc), address(weth), 0);
  }

  function testRevert_WhenLiquidationCallerIsNotOk() external {
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Unauthorized.selector));
    vm.prank(EVE);
    liquidationFacet.liquidationCall(address(0), ALICE, _subAccountId, address(usdc), address(weth), 0);
  }

  function testRevert_WhenTryToLiquidateNonExistedCollateral_ShouldRevert() external {
    // criteria
    address _collatToken = address(ibUsdc);
    address _debtToken = address(usdc);

    vm.prank(liquidator);
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_CollateralNotExist.selector));
    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      _subAccountId,
      _debtToken,
      _collatToken,
      0
    );
  }

  function testRevert_WhenLiquidateMoreThanThreshold() external {
    address _debtToken = address(usdc);
    address _collatToken = address(weth);

    // LiquidationFacet need these to function
    mockOracle.setTokenPrice(address(weth), 8e17);
    mockOracle.setTokenPrice(address(usdc), 1 ether);

    // alice has 40 weth collat, 30 usdc debt
    // liquidate 30 usdc debt should fail because liquidatedBorrowingPower > maxLiquidateBps * totalUsedBorrowingPower
    vm.prank(liquidator);
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_RepayAmountExceedThreshold.selector));
    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      _subAccountId,
      _debtToken,
      _collatToken,
      0
    );
  }
}
