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

struct CacheState {
  uint256 collat;
  uint256 subAccountCollat;
  uint256 debtShare;
  uint256 debtValue;
  uint256 subAccountDebtShare;
}

contract MoneyMarket_Liquidation_LiquidationTest is MoneyMarket_BaseTest {
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

  function testCorrectness_WhenPartialLiquidate_ShouldWork() external {
    /**
     * scenario:
     *
     * 1. 1 usdc/weth, ALICE post 40 weth as collateral, borrow 30 usdc
     *    - ALICE borrowing power = 40 * 1 * 9000 / 10000 = 36 usd
     *
     * 2. 1 day passesd, debt accrued, weth price drops to 0.8 usdc/weth, position become liquidatable
     *    - usdc debt has increased to 30.0050765511672 usdc
     *    - ALICE borrowing power = 40 * 0.8 * 9000 / 10000 = 28.8 usd
     *
     * 3. try to liquidate 15 usdc with weth collateral
     *
     * 4. should be able to liquidate with 15 usdc repaid and 18.9375 weth reduced from collateral
     *    - remaining collateral = 40 - 18.9375 = 21.0625 weth
     *      - 15 usdc = 18.75 weth is liquidated
     *      - 18.75 * 1% = 0.1875 weth is taken to treasury as liquidation fee
     *    - remaining debt value = 30.0050765511672 - 15 = 15.0050765511672 usdc
     *    - remaining debt share = 30 - 14.997462153866591690 = 15.00253784613340831 shares
     *      - repaid debt shares = amountRepaid * totalDebtShare / totalDebtValue = 15 * 30 / 30.0050765511672 = 14.997462153866591690
     */

    address _debtToken = address(usdc);
    address _collatToken = address(weth);

    vm.warp(block.timestamp + 1 days);

    // LiquidationFacet need these to function
    mockOracle.setTokenPrice(address(weth), 8e17);
    mockOracle.setTokenPrice(address(usdc), 1e18);

    uint256 _treasuryFeeBefore = MockERC20(_debtToken).balanceOf(treasury);

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

    assertEq(_stateAfter.collat, 21.0625 ether);
    assertEq(_stateAfter.subAccountCollat, 21.0625 ether);
    assertEq(_stateAfter.debtValue, 15.0050765511672 ether);
    assertEq(_stateAfter.debtShare, 15.00253784613340831 ether);
    assertEq(_stateAfter.subAccountDebtShare, 15.00253784613340831 ether);
    // globalDebt should equal to debtValue since there is only 1 position
    assertEq(viewFacet.getGlobalDebtValue(_debtToken), 15.0050765511672 ether);

    assertEq(MockERC20(_debtToken).balanceOf(treasury) - _treasuryFeeBefore, 0.15 ether);
  }

  function testCorrectness_InjectedCollatToStrat_ThenPartialLiquidate_ShouldWork() external {
    /**
     * scenario:
     *
     * 1. inject insane amount of collat to liquidation strat
     *
     * 2. 1 usdc/weth, ALICE post 40 weth as collateral, borrow 30 usdc
     *    - ALICE borrowing power = 40 * 1 * 9000 / 10000 = 36 usd
     *
     * 3. 1 day passesd, debt accrued, weth price drops to 0.8 usdc/weth, position become liquidatable
     *    - usdc debt has increased to 30.0050765511672 usdc
     *    - ALICE borrowing power = 40 * 0.8 * 9000 / 10000 = 28.8 usd
     *
     * 4. try to liquidate 15 usdc with weth collateral
     *
     * 5. should be able to liquidate with 15 usdc repaid and 18.9375 weth reduced from collateral
     *    - remaining collateral = 40 - 18.9375 = 21.0625 weth
     *      - 15 usdc = 18.75 weth is liquidated
     *      - 18.75 * 1% = 0.1875 weth is taken to treasury as liquidation fee
     *    - remaining debt value = 30.0050765511672 - 15 = 15.0050765511672 usdc
     *    - remaining debt share = 30 - 14.997462153866591690 = 15.00253784613340831 shares
     *      - repaid debt shares = amountRepaid * totalDebtShare / totalDebtValue = 15 * 30 / 30.0050765511672 = 14.997462153866591690
     */

    address _debtToken = address(usdc);
    address _collatToken = address(weth);
    uint256 _injectedCollatAmount = 10000 ether;

    vm.warp(block.timestamp + 1 days);

    // LiquidationFacet need these to function
    mockOracle.setTokenPrice(address(weth), 8e17);
    mockOracle.setTokenPrice(address(usdc), 1e18);
    weth.mint(address(mockLiquidationStrategy), _injectedCollatAmount);

    uint256 _treasuryFeeBefore = MockERC20(_debtToken).balanceOf(treasury);

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

    assertEq(_stateAfter.collat, 21.0625 ether);
    assertEq(_stateAfter.subAccountCollat, 21.0625 ether);
    assertEq(_stateAfter.debtValue, 15.0050765511672 ether);
    assertEq(_stateAfter.debtShare, 15.00253784613340831 ether);
    assertEq(_stateAfter.subAccountDebtShare, 15.00253784613340831 ether);

    assertEq(MockERC20(_debtToken).balanceOf(treasury) - _treasuryFeeBefore, 0.15 ether);
  }

  function testCorrectness_WhenLiquidateMoreThanDebt_ShouldLiquidateAllDebtOnThatToken() external {
    /**
     * scenario:
     *
     * 1. 1 usdc/weth, ALICE post 40 weth as collateral, borrow 30 usdc
     *    - ALICE borrowing power = 40 * 1 * 9000 / 10000 = 36 usd
     *
     * 2. 1 day passesd, debt accrued, weth price drops to 0.8 usdc/weth, position become liquidatable
     *    - usdc debt has increased to 30.0050765511672 usdc
     *    - ALICE borrowing power = 40 * 0.8 * 9000 / 10000 = 28.8 usd
     *
     * 3. try to liquidate 40 usdc with weth collateral
     *
     * 4. should be able to liquidate with 30.0050765511672 usdc repaid, 37.88140914584859 weth reduced from collateral and 0.300050765511672 usdc to treasury
     *    - remaining collateral = 40 - 37.88140914584859 = 2.11859085415141 weth
     *      - @0.8 usdc/weth 30.0050765511672 usdc = 37.506345688959 weth is liquidated
     *      - 30.0050765511672 * 1% = 0.300050765511672 usdc is taken to treasury as liquidation fee
     *      - total weth liquidated = 37.506345688959 + 0.300050765511672 = 37.88140914584859
     *    - remaining debt value = 0
     *    - remaining debt share = 0
     */

    adminFacet.setLiquidationParams(10000, 9000); // allow liquidation of entire subAccount

    address _debtToken = address(usdc);
    address _collatToken = address(weth);
    uint256 _repayAmount = 40 ether;

    vm.warp(block.timestamp + 1 days);

    // LiquidationFacet need these to function
    mockOracle.setTokenPrice(address(weth), 8e17);
    mockOracle.setTokenPrice(address(usdc), 1 ether);
    // MockLiquidationStrategy need these to function
    mockOracle.setTokenPrice(address(weth), 8e17);

    uint256 _treasuryFeeBefore = MockERC20(_debtToken).balanceOf(treasury);

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

    assertEq(_stateAfter.collat, 2.11859085415141 ether); // 40 - 37.88140914584859 = 2.11859085415141 weth remaining
    assertEq(_stateAfter.subAccountCollat, 2.11859085415141 ether); // same as collat
    // entire positon got liquidated, everything = 0
    assertEq(_stateAfter.debtValue, 0);
    assertEq(_stateAfter.debtShare, 0);
    assertEq(_stateAfter.subAccountDebtShare, 0);

    assertEq(MockERC20(_debtToken).balanceOf(treasury) - _treasuryFeeBefore, 0.300050765511672 ether);
  }

  function testCorrectness_WhenLiquidateAllCollateral_ShouldWorkButTreasuryReceiveNoFee() external {
    /**
     * scenario:
     *
     * 1. 1 usdc/weth, 10 usdc/btc, ALICE post 40 weth and 100 btc as collateral, borrow 80 usdc
     *    - borrowing power = 40 * 1 * 9000 / 10000 + 100 * 10 * 9000 / 10000 = 936 usd
     *
     * 2. 1 day passed, debt accrued, btc price drops to 0.1 usd/btc, position become liquidatable
     *    - usdc debt has increased to 80.036099919413504 usdc
     *      - 0.0004512489926688 is interest rate per day of (80% condition slope)
     *      - total debt value of usdc should increase by 0.0004512489926688 * 80 = 0.036099919413504
     *    - borrowing power = 40 * 1 * 9000 / 10000 + 100 * 0.1 * 9000 / 10000 = 45 usd
     *
     * 3. try to liquidate usdc debt with 40 weth
     *
     * 4. should be able to liquidate with 39.6 usdc repaid and 40 weth liquidated
     *    - remaining collateral = 0 weth
     *      - @1 usdc/weth 39.6 usdc = 39.6 weth is liquidated
     *      - 40 * 1% = 0.4 weth fee to treasury
     *    - remaining debt value = 80.036099919413504 - 39.6 = 40.436099919413504 usdc
     *    - remaining debt share = 80 - 39.981958181645606 ~= 40.41786140017084973 shares
     *      - repaid debt shares = amountRepaid * totalDebtShare / totalDebtValue = 39.6 * 80 / 80.036099919413504 = 39.582138599829150270272757155067956377008065689156955144328424412...
     */

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, 0, address(btc), 100 ether);
    borrowFacet.borrow(0, address(usdc), 50 ether);
    vm.stopPrank();

    address _debtToken = address(usdc);
    address _collatToken = address(weth);

    vm.warp(block.timestamp + 1 days);

    mockOracle.setTokenPrice(address(btc), 1e17);
    mockOracle.setTokenPrice(address(weth), 1 ether);
    mockOracle.setTokenPrice(address(usdc), 1 ether);

    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      _subAccountId,
      _debtToken,
      _collatToken,
      40 ether,
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

    assertEq(_stateAfter.collat, 0);
    assertEq(_stateAfter.subAccountCollat, 0);
    assertEq(_stateAfter.debtValue, 40.436099919413504 ether);
    assertEq(_stateAfter.debtShare, 40.41786140017084973 ether);
    assertEq(_stateAfter.subAccountDebtShare, 40.41786140017084973 ether);

    assertEq(MockERC20(_debtToken).balanceOf(treasury), 0.4 ether);
  }

  function testCorrectness_WhenLiquidationStrategyReturnRepayTokenLessThanExpected_AndNoCollatIsReturned_ShouldCauseBadDebt()
    external
  {
    adminFacet.setLiquidationParams(10000, 9000); // allow liquidation of entire subAccount

    address _debtToken = address(usdc);
    address _collatToken = address(weth);

    vm.warp(block.timestamp + 1 days);

    // LiquidationFacet need these to function
    mockOracle.setTokenPrice(address(weth), 8e17);
    mockOracle.setTokenPrice(address(usdc), 1 ether);

    uint256 _treasuryFeeBefore = MockERC20(_debtToken).balanceOf(treasury);

    liquidationFacet.liquidationCall(
      address(mockBadLiquidationStrategy), // this strategy return repayToken repayAmount - 1 and doesn't return collateral
      ALICE,
      _subAccountId,
      _debtToken,
      _collatToken,
      30 ether,
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

    // strategy doesn't return collat
    assertEq(_stateAfter.collat, 0);
    assertEq(_stateAfter.subAccountCollat, 0);
    // bad debt (0 collat with remaining debt)
    assertEq(_stateAfter.debtValue, 0.005076551167200001 ether); // 30.0050765511672 ether - (30 ether - 1 wei) because collat is enough to cover both debt and fee
    assertEq(_stateAfter.debtShare, 0.005075692266816620 ether); // wolfram: 30-(30-0.000000000000000001)*Divide[30,30.0050765511672]
    assertEq(_stateAfter.subAccountDebtShare, 0.005075692266816620 ether);

    assertEq(MockERC20(_debtToken).balanceOf(treasury) - _treasuryFeeBefore, 0.3 ether);
  }

  function testRevert_WhenLiquidateWhileSubAccountIsHealthy() external {
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Healthy.selector));
    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      _subAccountId,
      address(usdc),
      address(weth),
      1 ether,
      abi.encode()
    );

    // case borrowingPower == usedBorrowingPower * threshold
    vm.prank(ALICE);

    // note: have to borrow and lower price because doing just either borrow or increase price
    // won't be able to make both side equal

    // if we only set weth price to 0.8333..
    // there will be precision loss that make it impossible for both side to be equal
    // if we only borrow more it will hit borrow limit before reach equality

    // try to make borrowingPower = usedBorrowingPower * threshold = 32.4
    // borrow more to increase usedBorrowingPower to 36 ether -> 36 * 0.9 (threshold) = 32.4
    borrowFacet.borrow(0, address(usdc), 2.4 ether);

    // decrease price to lower borrowingPower to 32.4
    mockOracle.setTokenPrice(address(weth), 0.9 ether);

    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Healthy.selector));
    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      _subAccountId,
      address(usdc),
      address(weth),
      1 ether,
      abi.encode()
    );
  }

  function testRevert_WhenLiquidationStrategyIsNotOk() external {
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Unauthorized.selector));
    liquidationFacet.liquidationCall(
      address(0),
      ALICE,
      _subAccountId,
      address(usdc),
      address(weth),
      1 ether,
      abi.encode()
    );
  }

  function testRevert_WhenLiquidationCallerIsNotOk() external {
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Unauthorized.selector));
    vm.prank(EVE);
    liquidationFacet.liquidationCall(
      address(0),
      ALICE,
      _subAccountId,
      address(usdc),
      address(weth),
      1 ether,
      abi.encode()
    );
  }

  function testRevert_WhenLiquidateMoreThanThreshold() external {
    address _debtToken = address(usdc);
    address _collatToken = address(weth);
    uint256 _repayAmount = 30 ether;

    // LiquidationFacet need these to function
    mockOracle.setTokenPrice(address(weth), 8e17);
    mockOracle.setTokenPrice(address(usdc), 1 ether);

    // alice has 40 weth collat, 30 usdc debt
    // liquidate 30 usdc debt should fail because liquidatedBorrowingPower > maxLiquidateBps * totalUsedBorrowingPower
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
}
