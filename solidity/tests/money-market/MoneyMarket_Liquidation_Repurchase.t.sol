// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, console } from "./MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { IBorrowFacet, LibDoublyLinkedList } from "../../contracts/money-market/facets/BorrowFacet.sol";
import { ILiquidationFacet } from "../../contracts/money-market/facets/LiquidationFacet.sol";
import { IAdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";
import { TripleSlopeModel6, IInterestRateModel } from "../../contracts/money-market/interest-models/TripleSlopeModel6.sol";

struct CacheState {
  uint256 collat;
  uint256 subAccountCollat;
  uint256 debtShare;
  uint256 debtValue;
  uint256 subAccountDebtShare;
}

contract MoneyMarket_Liquidation_RepurchaseTest is MoneyMarket_BaseTest {
  using LibDoublyLinkedList for LibDoublyLinkedList.List;
  uint256 _subAccountId = 0;
  address _aliceSubAccount0 = LibMoneyMarket01.getSubAccount(ALICE, _subAccountId);
  address treasury;

  function setUp() public override {
    super.setUp();

    TripleSlopeModel6 _tripleSlope6 = new TripleSlopeModel6();
    adminFacet.setInterestModel(address(weth), address(_tripleSlope6));
    adminFacet.setInterestModel(address(btc), address(_tripleSlope6));
    adminFacet.setInterestModel(address(usdc), address(_tripleSlope6));

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

  function testCorrectness_ShouldRepurchasePassed_TransferTokenCorrectly() external {
    // criteria
    address _debtToken = address(usdc);
    address _collatToken = address(weth);

    uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);
    uint256 _bobWethBalanceBefore = weth.balanceOf(BOB);

    // collat amount should be = 40
    // collat debt value should be = 30
    // collat debt share should be = 30
    CacheState memory _stateBefore = CacheState({
      collat: viewFacet.getTotalCollat(_collatToken),
      subAccountCollat: viewFacet.getOverCollatSubAccountCollatAmount(_aliceSubAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateBefore.subAccountDebtShare, ) = viewFacet.getOverCollatSubAccountDebt(ALICE, 0, _debtToken);

    uint256 _treasuryFeeBefore = MockERC20(_debtToken).balanceOf(treasury);

    // add time 1 day
    // then total debt value should increase by 0.00016921837224 * 30 = 0.0050765511672
    vm.warp(block.timestamp + 1 days);

    // set price to weth from 1 to 0.8 ether USD
    // then alice borrowing power = 40 * 0.8 * 9000 / 10000 = 28.8 ether USD
    mockOracle.setTokenPrice(address(usdc), 1 ether);
    mockOracle.setTokenPrice(address(weth), 8e17);
    mockOracle.setTokenPrice(address(btc), 10 ether);

    // bob try repurchase with 15 usdc
    // eth price = 0.8 USD
    // usdc price = 1 USD
    // reward = 1%
    // repurchase fee = 1%
    // timestamp increased by 1 day, debt value should increased to 30.0050765511672
    // fee amount = 15 * 0.01 = 0.15
    uint256 _expectedFee = 0.15 ether;
    vm.prank(BOB);
    liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, 15 ether);

    // repay value = 15 * 1 = 1 USD
    // reward amount = 15 * 1.01 = 15.15 USD
    // converted weth amount = 15.15 / 0.8 = 18.9375

    uint256 _bobUsdcBalanceAfter = usdc.balanceOf(BOB);
    uint256 _bobWethBalanceAfter = weth.balanceOf(BOB);

    // check bob balance
    assertEq(_bobUsdcBalanceBefore - _bobUsdcBalanceAfter, 15 ether); // pay 15 usdc
    assertEq(_bobWethBalanceAfter - _bobWethBalanceBefore, 18.9375 ether); // get 18.9375 weth

    CacheState memory _stateAfter = CacheState({
      collat: viewFacet.getTotalCollat(_collatToken),
      subAccountCollat: viewFacet.getOverCollatSubAccountCollatAmount(_aliceSubAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatSubAccountDebt(ALICE, 0, _debtToken);

    // check state
    // note: before repurchase state should be like these
    // collat amount should be = 40
    // collat debt value should be = 30.0050765511672 (0.0050765511672 is fixed interest increased)
    // collat debt share should be = 30
    // then after repurchase
    // collat amount should be = 40 - (_collatAmountOut) = 40 - 18.9375 = 21.0625
    // actual repaid debt amount = _repayAmount - fee = 15 - 0.15 = 14.85
    // collat debt value should be = 30.0050765511672 - (actual repaid debt amount) = 30.0050765511672 - 14.85 = 15.1550765511672
    // _repayShare = actual repaid debt amount * totalDebtShare / totalDebtValue = 14.85 * 30 / 30.0050765511672 = 14.847487532327925774
    // collat debt share should be = 30 - (_repayShare) = 30 - 14.847487532327925774 = 15.152512467672074226
    assertEq(_stateAfter.collat, 21.0625 ether);
    assertEq(_stateAfter.subAccountCollat, 21.0625 ether);
    assertEq(_stateAfter.debtValue, 15.1550765511672 ether);
    assertEq(_stateAfter.debtShare, 15.152512467672074226 ether);
    assertEq(_stateAfter.subAccountDebtShare, 15.152512467672074226 ether);
    // globalDebt should equal to debtValue since there is only 1 position
    assertEq(viewFacet.getGlobalDebtValue(_debtToken), 15.1550765511672 ether);
    vm.stopPrank();

    assertEq(MockERC20(_debtToken).balanceOf(treasury) - _treasuryFeeBefore, _expectedFee);
  }

  function testCorrectness_ShouldRepurchasePassedWithMoreThan50PercentOfDebtToken_TransferTokenCorrectly() external {
    // alice add more collateral
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, 0, address(weth), 40 ether);
    // alice borrow more btc token as 30% of vault = 3 btc
    borrowFacet.borrow(0, address(btc), 3 ether);
    vm.stopPrank();

    // criteria
    address _debtToken = address(usdc);
    address _collatToken = address(weth);

    uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);
    uint256 _bobWethBalanceBefore = weth.balanceOf(BOB);

    // collat amount should be = 80 on weth
    // collat debt value should be | usdc: 30 | btc: 3 |
    // collat debt share should be | usdc: 30 | btc: 3 |
    CacheState memory _stateBefore = CacheState({
      collat: viewFacet.getTotalCollat(_collatToken),
      subAccountCollat: viewFacet.getOverCollatSubAccountCollatAmount(_aliceSubAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateBefore.subAccountDebtShare, ) = viewFacet.getOverCollatSubAccountDebt(ALICE, 0, _debtToken);

    uint256 _treasuryFeeBefore = MockERC20(_debtToken).balanceOf(treasury);

    // add time 1 day
    // 0.00016921837224 is interest rate per day of (30% condition slope)
    // then total debt value of usdc should increase by 0.00016921837224 * 30 = 0.0050765511672
    // then total debt value of btc should increase by 0.00016921837224 * 3 = 0.00050765511672
    vm.warp(block.timestamp + 1 days);

    // set price to weth from 1 to 0.8 ether USD
    // then alice borrowing power = 40 * 0.8 * 9000 / 10000 = 28.8 ether USD
    vm.prank(DEPLOYER);
    mockOracle.setTokenPrice(address(weth), 8e17);
    mockOracle.setTokenPrice(address(usdc), 1e18);
    mockOracle.setTokenPrice(address(btc), 10e18);
    vm.stopPrank();

    // bob try repurchase with 20 usdc
    // eth price = 0.8 USD
    // usdc price = 1 USD
    // reward = 1%
    // repurchase fee = 1%
    // timestamp increased by 1 day, usdc debt value should increased to 30.0050765511672
    // timestamp increased by 1 day, btc value should increased to 3.00050765511672
    // fee amount = 20 * 0.01 = 0.2
    uint256 _expectedFee = 0.2 ether;
    vm.prank(BOB);
    liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, 20 ether);

    // repay value = 20 * 1 = 1 USD
    // reward amount = 20 * 1.01 = 20.20 USD
    // converted weth amount = 20.20 / 0.8 = 25.25
    // fee amount = 20 * 0.01 = 0.2 ether

    uint256 _bobUsdcBalanceAfter = usdc.balanceOf(BOB);
    uint256 _bobWethBalanceAfter = weth.balanceOf(BOB);

    // check bob balance
    assertEq(_bobUsdcBalanceBefore - _bobUsdcBalanceAfter, 20 ether); // pay 20 usdc
    assertEq(_bobWethBalanceAfter - _bobWethBalanceBefore, 25.25 ether); // get 25.25 weth

    CacheState memory _stateAfter = CacheState({
      collat: viewFacet.getTotalCollat(_collatToken),
      subAccountCollat: viewFacet.getOverCollatSubAccountCollatAmount(_aliceSubAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatSubAccountDebt(ALICE, 0, _debtToken);

    // check state
    // note: before repurchase state should be like these
    // collat amount should be = 80 on weth
    // collat debt value should be | usdc: 30.0050765511672 | btc: 3.00050765511672 | after accure interest
    // collat debt share should be | usdc: 30 | btc: 3 |
    // then after repurchase
    // collat amount should be = 80 - (_collatAmountOut) = 80 - 25.25 = 54.75
    // actual repaid debt amount = (_repayAmount - fee) = 20 - 0.2 = 19.8
    // collat debt value should be = 30.0050765511672 - (actual repaid debt amount) = 30.0050765511672 - 19.8 = 10.2050765511672
    // _repayShare = (actual repaid debt amount) * totalDebtShare / totalDebtValue = 19.8 * 30 / 30.0050765511672 = 19.796650043103901032
    // collat debt share should be = 30 - (_repayShare) = 30 - 19.796650043103901032 = ~10.203349956896098968
    assertEq(_stateAfter.collat, 54.75 ether);
    assertEq(_stateAfter.subAccountCollat, 54.75 ether);
    assertEq(_stateAfter.debtValue, 10.2050765511672 ether);
    assertEq(_stateAfter.debtShare, 10.203349956896098968 ether);
    assertEq(_stateAfter.subAccountDebtShare, 10.203349956896098968 ether);

    // check state for btc should not be changed
    CacheState memory _btcState = CacheState({
      collat: viewFacet.getTotalCollat(address(btc)),
      subAccountCollat: viewFacet.getOverCollatSubAccountCollatAmount(_aliceSubAccount0, address(btc)),
      debtShare: viewFacet.getOverCollatTokenDebtShares(address(btc)),
      debtValue: viewFacet.getOverCollatDebtValue(address(btc)),
      subAccountDebtShare: 0
    });
    (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatSubAccountDebt(ALICE, 0, address(btc));
    assertEq(_btcState.collat, 0 ether);
    assertEq(_btcState.subAccountCollat, 0 ether);
    assertEq(_btcState.debtValue, 3.00050765511672 ether);
    assertEq(_btcState.debtShare, 3 ether);

    assertEq(MockERC20(_debtToken).balanceOf(treasury) - _treasuryFeeBefore, _expectedFee);
  }

  function testCorrectness_ShouldRepurchasePassedWithMoreThanDebtTokenAmount_TransferTokenCorrectly() external {
    // alice add more collateral
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, 0, address(weth), 60 ether);
    // alice borrow more btc token as 50% of vault = 5 btc
    borrowFacet.borrow(0, address(btc), 5 ether);
    vm.stopPrank();

    // criteria
    address _debtToken = address(usdc);
    address _collatToken = address(weth);

    uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);
    uint256 _bobWethBalanceBefore = weth.balanceOf(BOB);

    // collat amount should be = 100 on weth
    // collat debt value should be | usdc: 30 | btc: 5 |
    // collat debt share should be | usdc: 30 | btc: 5 |
    CacheState memory _stateBefore = CacheState({
      collat: viewFacet.getTotalCollat(_collatToken),
      subAccountCollat: viewFacet.getOverCollatSubAccountCollatAmount(_aliceSubAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateBefore.subAccountDebtShare, ) = viewFacet.getOverCollatSubAccountDebt(ALICE, 0, _debtToken);

    uint256 _treasuryFeeBefore = MockERC20(_debtToken).balanceOf(treasury);

    // set price to weth from 1 to 0.8 ether USD
    // then alice borrowing power = 80 * 0.8 * 9000 / 10000 = 57.6 ether USD

    mockOracle.setTokenPrice(address(weth), 8e17);

    // add time 1 day
    // 0.00016921837224 is interest rate per day of (30% condition slope)
    // 0.0002820306204288 is interest rate per day of (50% condition slope)
    // then total debt value of usdc should increase by 0.00016921837224 * 30 = 0.0050765511672
    // then total debt value of btc should increase by 0.0002820306204288 * 5 = 0.001410153102144
    vm.warp(block.timestamp + 1 days);

    // set price to weth from 1 to 0.8 ether USD
    // then alice borrowing power = 40 * 0.8 * 9000 / 10000 = 28.8 ether USD

    mockOracle.setTokenPrice(address(weth), 8e17);
    mockOracle.setTokenPrice(address(usdc), 1 ether);
    mockOracle.setTokenPrice(address(btc), 10e18);

    // bob try repurchase with 40 usdc
    // eth price = 0.8 USD
    // usdc price = 1 USD
    // reward = 0.01%
    // repurchase fee = 1%
    // timestamp increased by 1 day, usdc debt value should increased to 30.0050765511672
    // timestamp increased by 1 day, btc value should increased to 5.001410153102144
    vm.prank(BOB);
    liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, 40 ether);

    // alice just have usdc debt 30.0050765511672 (with interest)
    // when repay amount (40) > _debtValue + fee (30.0050765511672 + 0.300050765511672) = 30.305127316678872
    // then actual repay amount should be 30.305127316678872
    // repay value = 30.305127316678872 * 1 = 30.305127316678872 USD
    // reward amount = 30.305127316678872 * 1.01 = 30.60817858984566072 USD
    // converted weth amount = 30.60817858984566072 / 0.8 = 38.2602232373070759
    // fee amount = 30.305127316678872 * 0.01 = 0.300050765511672
    uint256 _expectedFee = 0.300050765511672 ether;
    uint256 _bobUsdcBalanceAfter = usdc.balanceOf(BOB);
    uint256 _bobWethBalanceAfter = weth.balanceOf(BOB);

    // check bob balance
    assertEq(_bobUsdcBalanceBefore - _bobUsdcBalanceAfter, 30.305127316678872 ether); // pay 30.305127316678872
    assertEq(_bobWethBalanceAfter - _bobWethBalanceBefore, 38.2602232373070759 ether); // get 38.2602232373070759 weth

    CacheState memory _stateAfter = CacheState({
      collat: viewFacet.getTotalCollat(_collatToken),
      subAccountCollat: viewFacet.getOverCollatSubAccountCollatAmount(_aliceSubAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatSubAccountDebt(ALICE, 0, _debtToken);

    // check state
    // note: before repurchase state should be like these
    // collat amount should be = 100 on weth
    // collat debt value should be | usdc: 30.0050765511672 | btc: 5.001410153102144 | after accure interest
    // collat debt share should be | usdc: 30 | btc: 5 |
    // then after repurchase
    // collat amount should be = 100 - (_collatAmountOut) = 100 - 38.2602232373070759 = 61.7397767626929241
    // actual repaid debt amount = (_repayAmount - fee) = 30.308158132492121212 - 0.303081581324921212 = 30.0050765511672
    // collat debt value should be = 30.0050765511672 - (actual repaid debt amount) = 30.0050765511672 - 30.0050765511672 = 0
    // _repayShare = actual repaid debt amount * totalDebtShare / totalDebtValue = 30.0050765511672 * 30 / 30.0050765511672 = 30
    // collat debt share should be = 30 - (_repayShare) = 30 - 30 = 0
    assertEq(_stateAfter.collat, 61.7397767626929241 ether);
    assertEq(_stateAfter.subAccountCollat, 61.7397767626929241 ether);
    assertEq(_stateAfter.debtValue, 0);
    assertEq(_stateAfter.debtShare, 0);
    assertEq(_stateAfter.subAccountDebtShare, 0);

    // check state for btc should not be changed
    CacheState memory _btcState = CacheState({
      collat: viewFacet.getTotalCollat(address(btc)),
      subAccountCollat: viewFacet.getOverCollatSubAccountCollatAmount(_aliceSubAccount0, address(btc)),
      debtShare: viewFacet.getOverCollatTokenDebtShares(address(btc)),
      debtValue: viewFacet.getOverCollatDebtValue(address(btc)),
      subAccountDebtShare: 0
    });
    (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatSubAccountDebt(ALICE, 0, address(btc));
    assertEq(_btcState.collat, 0 ether);
    assertEq(_btcState.subAccountCollat, 0 ether);
    assertEq(_btcState.debtValue, 5.001410153102144 ether);
    assertEq(_btcState.debtShare, 5 ether);

    assertEq(MockERC20(_debtToken).balanceOf(treasury) - _treasuryFeeBefore, _expectedFee);
  }

  function testRevert_ShouldRevertIfSubAccountIsHealthy() external {
    // criteria
    address _debtToken = address(usdc);
    address _collatToken = address(weth);

    vm.prank(BOB);
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Healthy.selector));
    // bob try repurchase with 2 usdc
    liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, 2 ether);

    // case borrowingPower == usedBorrowingPower
    // borrow more to increase usedBorrowingPower to be equal to totalBorrowingPower
    // ALICE borrow 32.4 usdc convert to usedBorrowingPower = 32.4 * 10000 / 9000 = 36 USD
    vm.prank(ALICE);
    borrowFacet.borrow(0, address(usdc), 2.4 ether);

    vm.prank(BOB);
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Healthy.selector));
    liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, 2 ether);
  }

  function testRevert_ShouldRevertRepurchaserIsNotOK() external {
    // criteria
    address _debtToken = address(usdc);
    address _collatToken = address(weth);

    vm.startPrank(CAT);
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Unauthorized.selector));
    // bob try repurchase with 2 usdc
    liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, 2 ether);
    vm.stopPrank();
  }

  function testRevert_shouldRevertIfRepayIsTooHigh() external {
    // criteria
    address _debtToken = address(usdc);
    address _collatToken = address(weth);

    // collat amount should be = 40
    // collat debt value should be = 30
    // collat debt share should be = 30
    CacheState memory _stateBefore = CacheState({
      collat: viewFacet.getTotalCollat(_collatToken),
      subAccountCollat: viewFacet.getOverCollatSubAccountCollatAmount(_aliceSubAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateBefore.subAccountDebtShare, ) = viewFacet.getOverCollatSubAccountDebt(ALICE, 0, _debtToken);

    // add time 1 day
    // then total debt value should increase by 0.00016921837224 * 30 = 0.0050765511672
    vm.warp(1 days + 1);

    // set price to weth from 1 to 0.8 ether USD
    // then alice borrowing power = 40 * 0.8 * 9000 / 10000 = 28.8 ether USD

    mockOracle.setTokenPrice(address(weth), 8e17);
    mockOracle.setTokenPrice(address(usdc), 1 ether);
    mockOracle.setTokenPrice(address(btc), 10e18);

    // bob try repurchase with 2 usdc
    // eth price = 0.8 USD
    // usdc price = 1 USD
    // reward = 0.01%
    // timestamp increased by 1 day, debt value should increased to 30.0050765511672
    vm.startPrank(BOB);
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_RepayAmountExceedThreshold.selector));
    // bob try repurchase with 20 usdc but borrowed value is 30.0050765511672 / 2 = 15.0025382755836,
    // so bob can't pay more than 15.0025382755836 followed by condition (!> 50% of borrowed value)
    liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, 20 ether);
    vm.stopPrank();
  }

  function testRevert_ShouldRevertIfInsufficientCollateralAmount() external {
    vm.startPrank(ALICE);
    // alice has 36 ether USD power from eth
    // alice add more collateral in other assets
    // then borrowing power will be increased by 100 * 10 * 9000 / 10000 = 900 ether USD
    // total borrowing power is 936 ether USD
    collateralFacet.addCollateral(ALICE, 0, address(btc), 100 ether);
    // alice borrow more usdc token more 50% of vault = 50 usdc
    // alice used borrowed value is ~80
    borrowFacet.borrow(0, address(usdc), 50 ether);
    vm.stopPrank();

    // criteria
    address _debtToken = address(usdc);
    address _collatToken = address(weth);

    // add time 1 day
    // 0.0004512489926688 is interest rate per day of (80% condition slope)
    // then total debt value of usdc should increase by 0.0004512489926688 * 80 = 0.036099919413504
    vm.warp(1 days + 1);

    // set price to btc from 10 to 0.1 ether USD
    // then alice borrowing power from btc = 100 * 0.1 * 9000 / 10000 = 9 ether USD
    // total borrowing power is 36 + 9 = 45 ether USD
    mockOracle.setTokenPrice(address(btc), 1e17);
    mockOracle.setTokenPrice(address(weth), 1e18);
    mockOracle.setTokenPrice(address(usdc), 1e18);

    // bob try repurchase with 40 usdc
    // eth price = 0.2 USD
    // usdc price = 1 USD
    // reward = 0.01%
    // timestamp increased by 1 day, usdc debt value should increased to 80.036099919413504
    vm.startPrank(BOB);

    // repay value = 40 * 1 = 40 USD
    // reward amount = 40 * 1.01 = 40.40 USD
    // converted weth amount = 40.40 / 1 = 40.40
    // should revert because alice has eth collat just 40
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_InsufficientAmount.selector));
    liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, 40 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenRepurchaseAndRepayTokenAndCollatTokenAreSame_TransferTokenCorrectly() external {
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, 0, address(usdc), 20 ether);

    borrowFacet.borrow(0, address(usdc), 10 ether);
    // Now!!, alice borrowed 40% of vault then interest be 0.082352941146288000 per year
    // interest per day ~ 0.000225624496291200
    vm.stopPrank();

    // criteria
    address _debtToken = address(usdc);
    address _collatToken = address(usdc);

    uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);

    // collat (weth) amount should be = 40
    // collat (usdc) amount should be = 20
    // collat debt value should be = 40
    // collat debt share should be = 40
    CacheState memory _stateBefore = CacheState({
      collat: viewFacet.getTotalCollat(_collatToken),
      subAccountCollat: viewFacet.getOverCollatSubAccountCollatAmount(_aliceSubAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateBefore.subAccountDebtShare, ) = viewFacet.getOverCollatSubAccountDebt(ALICE, 0, _debtToken);

    uint256 _treasuryFeeBefore = MockERC20(_debtToken).balanceOf(treasury);

    // add time 1 day
    // then total debt value should increase by 0.000225624496291200 * 40 = 0.009024979851648
    vm.warp(block.timestamp + 1 days);

    // set price to weth from 1 to 0.8 ether USD
    // then alice borrowing power (weth) = 40 * 0.6 * 9000 / 10000 = 21.6 ether USD
    // then alice borrowing power (usdc) = 20 * 1 * 9000 / 10000 = 18 ether USD
    // total = 28.8 + 18 = 46.8 ether USD
    mockOracle.setTokenPrice(address(usdc), 1 ether);
    mockOracle.setTokenPrice(address(weth), 6e17);
    mockOracle.setTokenPrice(address(btc), 10 ether);

    // bob try repurchase with 15 usdc
    // eth price = 0.8 USD
    // usdc price = 1 USD
    // reward = 1%
    // repurchase fee = 1%
    // timestamp increased by 1 day, debt value should increased to 30.009024979851648
    // fee amount = 15 * 0.01 = 0.15
    uint256 _expectedFee = 0.15 ether;
    vm.prank(BOB);
    liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, 15 ether);

    // repay value = 15 * 1 = 1 USD
    // reward amount = 15 * 1.01 = 15.15 USD
    // converted usdc amount = 15.15 / 1 = 15.15 ether

    uint256 _bobUsdcBalanceAfter = usdc.balanceOf(BOB);

    // check bob balance
    assertEq(_bobUsdcBalanceAfter - _bobUsdcBalanceBefore, _expectedFee); // pay 15 usdc and get reward 15.15 usdc

    CacheState memory _stateAfter = CacheState({
      collat: viewFacet.getTotalCollat(_collatToken),
      subAccountCollat: viewFacet.getOverCollatSubAccountCollatAmount(_aliceSubAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatSubAccountDebt(ALICE, 0, _debtToken);

    // check state
    // note: before repurchase state should be like these
    // collat amount (usdc) should be = 20
    // collat debt value should be = 40.009024979851648 (0.009024979851648 is fixed interest increased)
    // collat debt share should be = 40
    // then after repurchase
    // collat amount should be = 20 - (_collatAmountOut) = 20 - 15.15 = 4.85
    // actual repaid debt amount = _repayAmount - fee = 15 - 0.15 = 14.85
    // collat debt value should be = 40.009024979851648 - (actual repaid debt amount) = 40.009024979851648 - 14.85 = 25.159024979851648
    // _repayShare = actual repaid debt amount * totalDebtShare / totalDebtValue = 14.85 * 40 / 40.009024979851648 = 14.846650232019788907
    // collat debt share should be = 40 - (_repayShare) = 40 - 14.846650232019788907 = 25.153349767980211093
    assertEq(_stateAfter.collat, 4.85 ether);
    assertEq(_stateAfter.subAccountCollat, 4.85 ether);
    assertEq(_stateAfter.debtValue, 25.159024979851648 ether);
    assertEq(_stateAfter.debtShare, 25.153349767980211093 ether);
    assertEq(_stateAfter.subAccountDebtShare, 25.153349767980211093 ether);
    // globalDebt should equal to debtValue since there is only 1 position
    assertEq(viewFacet.getGlobalDebtValue(_debtToken), 25.159024979851648 ether);

    assertEq(MockERC20(_debtToken).balanceOf(treasury) - _treasuryFeeBefore, _expectedFee);
  }
}
