// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, console } from "./MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { ILiquidationFacet } from "../../contracts/money-market/facets/LiquidationFacet.sol";
import { TripleSlopeModel6, IInterestRateModel } from "../../contracts/money-market/interest-models/TripleSlopeModel6.sol";

// mocks
import { MockLiquidationStrategy } from "../mocks/MockLiquidationStrategy.sol";
import { MockBadLiquidationStrategy } from "../mocks/MockBadLiquidationStrategy.sol";
import { MockInterestModel } from "../mocks/MockInterestModel.sol";

struct CacheState {
  uint256 collat;
  uint256 subAccountCollat;
  uint256 debtShare;
  uint256 debtValue;
  uint256 subAccountDebtShare;
}

contract MoneyMarket_Liquidation_IbLiquidationTest is MoneyMarket_BaseTest {
  uint256 _subAccountId = 0;
  address _aliceSubAccount0 = LibMoneyMarket01.getSubAccount(ALICE, _subAccountId);
  MockLiquidationStrategy internal mockLiquidationStrategy;
  MockBadLiquidationStrategy internal mockBadLiquidationStrategy;
  address treasury;

  function setUp() public override {
    super.setUp();

    TripleSlopeModel6 tripleSlope6 = new TripleSlopeModel6();
    adminFacet.setInterestModel(address(weth), address(tripleSlope6));
    adminFacet.setInterestModel(address(btc), address(tripleSlope6));
    adminFacet.setInterestModel(address(usdc), address(tripleSlope6));

    // setup liquidationStrategy
    mockLiquidationStrategy = new MockLiquidationStrategy(address(mockOracle));
    usdc.mint(address(mockLiquidationStrategy), 1000 ether);
    mockBadLiquidationStrategy = new MockBadLiquidationStrategy();
    usdc.mint(address(mockBadLiquidationStrategy), 1000 ether);

    address[] memory _liquidationStrats = new address[](2);
    _liquidationStrats[0] = address(mockLiquidationStrategy);
    _liquidationStrats[1] = address(mockBadLiquidationStrategy);
    adminFacet.setLiquidationStratsOk(_liquidationStrats, true);

    address[] memory _liquidationCallers = new address[](2);
    _liquidationCallers[0] = BOB;
    _liquidationCallers[1] = address(this);
    adminFacet.setLiquidatorsOk(_liquidationCallers, true);

    vm.startPrank(DEPLOYER);
    mockOracle.setTokenPrice(address(btc), 10 ether);
    vm.stopPrank();

    // bob deposit 100 usdc and 10 btc
    vm.startPrank(BOB);
    lendFacet.deposit(address(usdc), 100 ether);
    lendFacet.deposit(address(btc), 10 ether);
    vm.stopPrank();

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, 0, address(weth), 40 ether);
    // alice added collat 40 ether
    // given collateralFactor = 9000, weth price = 1
    // then alice got power = 40 * 1 * 9000 / 10000 = 36 ether USD
    // alice borrowed 30% of vault then interest should be 0.0617647058676 per year
    // interest per day = 0.00016921837224
    borrowFacet.borrow(0, address(usdc), 30 ether);
    vm.stopPrank();

    treasury = address(this);
  }

  function testCorrectness_WhenPartialLiquidateIbCollateral_ShouldRedeemUnderlyingToPayDebtCorrectly() external {
    // add ib as collat
    vm.startPrank(ALICE);
    lendFacet.deposit(address(weth), 40 ether);
    collateralFacet.addCollateral(ALICE, 0, address(ibWeth), 40 ether);
    collateralFacet.removeCollateral(_subAccountId, address(weth), 40 ether);
    vm.stopPrank();

    // criteria
    address _debtToken = address(usdc);
    address _collatToken = address(ibWeth);

    // add time 1 day
    // then total debt value should increase by 0.00016921837224 * 30 = 0.0050765511672
    vm.warp(block.timestamp + 1 days);

    // increase shareValue of ibWeth by 2.5%
    // would need 18.2926829268... ibWeth to redeem 18.75 weth to repay debt
    vm.prank(BOB);
    lendFacet.deposit(address(weth), 1 ether);
    vm.prank(moneyMarketDiamond);
    ibWeth.onWithdraw(BOB, BOB, 0, 1 ether);

    // mm state before
    uint256 _totalSupplyIbWethBefore = ibWeth.totalSupply();
    uint256 _totalWethInMMBefore = weth.balanceOf(address(moneyMarketDiamond));
    uint256 _treasuryFeeBefore = MockERC20(_debtToken).balanceOf(treasury);

    mockOracle.setTokenPrice(address(weth), 8e17);
    mockOracle.setTokenPrice(address(usdc), 1 ether);

    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      _subAccountId,
      _debtToken,
      _collatToken,
      15 ether,
      abi.encode()
    );

    CacheState memory _stateAfter = CacheState({
      collat: viewFacet.getTotalCollat(_collatToken),
      subAccountCollat: viewFacet.getOverCollatSubAccountCollatAmount(_aliceSubAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatSubAccountDebt(ALICE, 0, _debtToken);

    assertEq(_stateAfter.collat, 21.524390243902439025 ether); // 21.5243902439024 repeating
    assertEq(_stateAfter.subAccountCollat, 21.524390243902439025 ether); // 21.5243902439024 repeating
    assertEq(_stateAfter.debtValue, 15.0050765511672 ether); // same as other cases
    assertEq(_stateAfter.debtShare, 15.00253784613340831 ether);
    assertEq(_stateAfter.subAccountDebtShare, 15.00253784613340831 ether);

    // check mm state after
    assertEq(_totalSupplyIbWethBefore - ibWeth.totalSupply(), 18.475609756097560975 ether); // ibWeth repaid + liquidation fee
    assertEq(_totalWethInMMBefore - weth.balanceOf(address(moneyMarketDiamond)), 18.9375 ether); // weth repaid + liquidation fee

    assertEq(MockERC20(_debtToken).balanceOf(treasury) - _treasuryFeeBefore, 0.15 ether); // fee 0.15 usdc = 0.1875 weth
  }

  function testCorrectness_WhenLiquidateIbMoreThanDebt_ShouldLiquidateAllDebtOnThatToken() external {
    /**
     * todo: simulate if weth has debt, should still correct
     * scenario:
     *
     * 1. 1 usdc/weth, ALICE post 40 ibWeth (value 40 weth) as collateral, borrow 30 usdc
     *    - ALICE borrowing power = 40 * 1 * 9000 / 10000 = 36 usd
     *
     * 2. 1 day passesd, debt accrued, weth price drops to 0.8 usdc/weth, increase shareValue of ibWeth by 2.5%, position become liquidatable
     *    - usdc debt has increased to 30.0050765511672 usdc
     *    - now 1 ibWeth = 1.025 weth
     *    - ALICE borrowing power = 41 * 0.8 * 9000 / 10000 = 29.52 usd
     *
     * 3. try to liquidate 40 usdc with ibWeth collateral
     *    - entire 30.0050765511672 usdc position should be liquidated
     *
     * 4. should be able to liquidate with 30.0050765511672 usdc repaid and 36.957472337413258535 ibWeth reduced from collateral
     *    - remaining collateral = 41 - 36.957472337413258535 = 3.042527662586741465 ibWeth
     *      - 30.0050765511672 usdc = 37.506345688959 weth = 36.5915567697160975... ibWeth is liquidated
     *      - 30.0050765511672 * 1% = 0.300050765511672 usdc is taken to treasury as liquidation fee
     *    - remaining debt value = 0 usdc
     *    - remaining debt share = 0 shares
     */

    adminFacet.setLiquidationParams(10000, 9000); // allow liquidation of entire subAccount

    // add ib as collat
    vm.startPrank(ALICE);
    lendFacet.deposit(address(weth), 40 ether);
    collateralFacet.addCollateral(ALICE, 0, address(ibWeth), 40 ether);
    collateralFacet.removeCollateral(_subAccountId, address(weth), 40 ether);
    vm.stopPrank();

    address _debtToken = address(usdc);
    address _collatToken = address(ibWeth);
    uint256 _repayAmount = 40 ether;

    vm.warp(block.timestamp + 1 days);

    // increase shareValue of ibWeth by 2.5%
    // would need 36.5915567697161341463414634... ibWeth to redeem 37.506345688959 weth to repay debt
    vm.prank(BOB);
    lendFacet.deposit(address(weth), 1 ether);
    vm.prank(moneyMarketDiamond);
    ibWeth.onWithdraw(BOB, BOB, 0, 1 ether);

    // mm state before
    uint256 _totalSupplyIbWethBefore = ibWeth.totalSupply();
    uint256 _totalWethInMMBefore = weth.balanceOf(address(moneyMarketDiamond));
    uint256 _treasuryFeeBefore = MockERC20(_debtToken).balanceOf(treasury);

    // set price to weth from 1 to 0.8 ether USD
    // then alice borrowing power = 41 * 0.8 * 9000 / 10000 = 29.52 ether USD
    mockOracle.setTokenPrice(address(weth), 8e17);
    mockOracle.setTokenPrice(address(usdc), 1e18);

    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      _subAccountId,
      _debtToken,
      _collatToken,
      _repayAmount,
      abi.encode()
    );

    CacheState memory _stateAfter = CacheState({
      collat: viewFacet.getTotalCollat(_collatToken),
      subAccountCollat: viewFacet.getOverCollatSubAccountCollatAmount(_aliceSubAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatSubAccountDebt(ALICE, 0, _debtToken);

    assertEq(_stateAfter.collat, 3.042527662586741464 ether); // 3.04252766258674146341... repeat 46341
    assertEq(_stateAfter.subAccountCollat, 3.042527662586741464 ether); // 3.04252766258674146341... repeat 46341
    assertEq(_stateAfter.debtValue, 0);
    assertEq(_stateAfter.debtShare, 0);
    assertEq(_stateAfter.subAccountDebtShare, 0);

    // check mm state after
    assertEq(_totalSupplyIbWethBefore - ibWeth.totalSupply(), 36.957472337413258536 ether); // ibWeth repaid + liquidation fee
    assertEq(_totalWethInMMBefore - weth.balanceOf(address(moneyMarketDiamond)), 37.88140914584859 ether); // weth repaid + liquidation fee

    assertEq(MockERC20(_debtToken).balanceOf(treasury) - _treasuryFeeBefore, 0.300050765511672 ether);
  }

  function testRevert_WhenLiquidateButMMDoesNotHaveEnoughUnderlyingForLiquidation() external {
    vm.startPrank(ALICE);
    lendFacet.deposit(address(weth), 40 ether);
    collateralFacet.addCollateral(ALICE, 0, address(ibWeth), 40 ether);
    collateralFacet.removeCollateral(_subAccountId, address(weth), 40 ether);
    vm.stopPrank();

    vm.warp(1 days + 1);

    mockOracle.setTokenPrice(address(weth), 1 ether);
    mockOracle.setTokenPrice(address(usdc), 1 ether);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, 0, address(usdc), 100 ether);
    borrowFacet.borrow(0, address(weth), 30 ether);
    vm.stopPrank();

    vm.prank(BOB);
    lendFacet.deposit(address(weth), 1 ether);
    vm.prank(moneyMarketDiamond);
    ibWeth.onWithdraw(BOB, BOB, 0, 1 ether);

    mockOracle.setTokenPrice(address(weth), 8e17);
    // todo: check this

    // should fail because 11 weth left in mm not enough to liquidate 15 usdc debt
    vm.expectRevert("!safeTransfer");
    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      _subAccountId,
      address(usdc),
      address(ibWeth),
      15 ether,
      abi.encode()
    );
  }

  function testRevert_WhenLiquidateIbWhileSubAccountIsHealthy() external {
    // add ib as collat
    vm.startPrank(ALICE);
    lendFacet.deposit(address(weth), 40 ether);
    collateralFacet.addCollateral(ALICE, 0, address(ibWeth), 40 ether);
    collateralFacet.removeCollateral(_subAccountId, address(weth), 40 ether);
    vm.stopPrank();

    // increase shareValue of ibWeth by 2.5%
    // wouldn need 18.475609756097... ibWeth to redeem 18.9375 weth to repay debt
    vm.prank(BOB);
    lendFacet.deposit(address(weth), 4 ether);
    vm.prank(moneyMarketDiamond);
    ibWeth.onWithdraw(BOB, BOB, 0, 4 ether);
    // set price to weth from 1 to 0.8 ether USD
    // since ibWeth collat value increase, alice borrowing power = 44 * 0.8 * 9000 / 10000 = 31.68 ether USD
    mockOracle.setTokenPrice(address(weth), 8e17);
    mockOracle.setTokenPrice(address(usdc), 1e18);
    mockOracle.setTokenPrice(address(btc), 10 ether);

    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Healthy.selector));
    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      _subAccountId,
      address(usdc),
      address(ibWeth),
      1 ether,
      abi.encode()
    );
  }

  function testRevert_WhenIbLiquidateMoreThanThreshold() external {
    vm.startPrank(ALICE);
    lendFacet.deposit(address(weth), 40 ether);
    collateralFacet.addCollateral(ALICE, 0, address(ibWeth), 40 ether);
    collateralFacet.removeCollateral(_subAccountId, address(weth), 40 ether);
    vm.stopPrank();

    address _debtToken = address(usdc);
    address _collatToken = address(ibWeth);
    uint256 _repayAmount = 30 ether;

    mockOracle.setTokenPrice(address(weth), 8e17);
    mockOracle.setTokenPrice(address(usdc), 1e18);

    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_RepayAmountExceedThreshold.selector));
    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      _subAccountId,
      _debtToken,
      _collatToken,
      _repayAmount,
      abi.encode()
    );
  }

  function testCorrectness_WhenIbLiquidateWithDebtAndInterestOnIb_ShouldAccrueInterestAndLiquidate() external {
    /**
     * scenario
     *
     * 1. ALICE add 1.5 ibWeth as collateral, borrow 1 usdc
     *    - borrowing power = 1.5 * 1 * 9000 / 10000 = 1.35
     *    - used borrowing power = 1 * 1 * 10000 / 9000 = 1.111..
     *
     * 2. BOB add 10 usdc as collateral, borrow 0.1 weth
     *
     * 3. 1 block passed, interest accrue on weth 0.001, usdc 0.01
     *    - note that in mm base test had lendingFee set to 0. has to account for if not 0
     *
     * 4. weth price dropped to 0.1 usdc/weth, ALICE position is liquidatable
     *    - ALICE borrowing power = 1.5 * 0.1 * 9000 / 10000 = 0.135
     *
     * 5. liquidate entire position by dumping 1.5 ibWeth to 0.150075 usdc
     *    - ibWeth collateral = 1.5 ibWeth = 1.50075 weth = 0.150075 usdc
     *
     * 6. state after liquidation
     *    - collat = 0
     *    - liquidation fee = 1.01 * 0.01 = 0.0101 usdc
     *    - remaining debt value = 1.01 - (0.150075 - 0.0101) = 0.870025 usdc
     */
    address _collatToken = address(ibWeth);
    address _debtToken = address(usdc);

    MockInterestModel _interestModel = new MockInterestModel(0.01 ether);
    adminFacet.setInterestModel(address(weth), address(_interestModel));
    adminFacet.setInterestModel(address(usdc), address(_interestModel));

    vm.startPrank(ALICE);
    lendFacet.deposit(address(weth), 2 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 1.5 ether);
    borrowFacet.repay(ALICE, subAccount0, _debtToken, 29 ether);
    collateralFacet.removeCollateral(subAccount0, address(weth), 40 ether);
    vm.stopPrank();

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), 10 ether);
    borrowFacet.borrow(subAccount0, address(weth), 0.1 ether);
    vm.stopPrank();

    vm.warp(block.timestamp + 1);

    assertEq(viewFacet.getGlobalPendingInterest(address(usdc)), 0.01 ether); // from ALICE
    assertEq(viewFacet.getGlobalPendingInterest(address(weth)), 0.001 ether); // from BOB

    mockOracle.setTokenPrice(address(weth), 0.1 ether);

    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      _subAccountId,
      _debtToken,
      _collatToken,
      2 ether,
      abi.encode()
    );

    // ALICE is rekt
    assertEq(viewFacet.getOverCollatSubAccountCollatAmount(_aliceSubAccount0, _collatToken), 0);
    (, uint256 _debtAmount) = viewFacet.getOverCollatSubAccountDebt(ALICE, subAccount0, _debtToken);
    assertEq(_debtAmount, 0.870025 ether);

    // check mm state
    assertEq(viewFacet.getTotalCollat(_collatToken), 0);
    assertEq(viewFacet.getOverCollatDebtValue(_debtToken), 0.870025 ether);
    // accrue weth properly
    assertEq(viewFacet.getGlobalPendingInterest(address(weth)), 0);
    assertEq(viewFacet.getDebtLastAccrueTime(address(weth)), block.timestamp);
    assertEq(viewFacet.getTotalToken(address(weth)), 0.50025 ether); // 2.001 - 1.50075
    assertEq(viewFacet.getTotalTokenWithPendingInterest(address(weth)), 0.50025 ether); // 2.001 - 1.50075
  }

  // TODO: case where diamond has no actual token to transfer to strat
}
