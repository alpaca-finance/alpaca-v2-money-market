// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, DebtToken, console } from "../MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { IBorrowFacet, LibDoublyLinkedList } from "../../../contracts/money-market/facets/BorrowFacet.sol";
import { ILiquidationFacet } from "../../../contracts/money-market/facets/LiquidationFacet.sol";
import { IAdminFacet } from "../../../contracts/money-market/facets/AdminFacet.sol";
import { TripleSlopeModel6, IInterestRateModel } from "../../../contracts/money-market/interest-models/TripleSlopeModel6.sol";
import { FixedFeeModel, IFeeModel } from "../../../contracts/money-market/fee-models/FixedFeeModel.sol";
import { IMiniFL } from "../../../contracts/money-market/interfaces/IMiniFL.sol";

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
  IMiniFL internal _miniFL;

  function setUp() public override {
    super.setUp();

    _miniFL = IMiniFL(address(miniFL));

    TripleSlopeModel6 _tripleSlope6 = new TripleSlopeModel6();
    adminFacet.setInterestModel(address(weth), address(_tripleSlope6));
    adminFacet.setInterestModel(address(btc), address(_tripleSlope6));
    adminFacet.setInterestModel(address(usdc), address(_tripleSlope6));

    FixedFeeModel fixedFeeModel = new FixedFeeModel();
    adminFacet.setRepurchaseRewardModel(fixedFeeModel);

    vm.startPrank(DEPLOYER);
    mockOracle.setTokenPrice(address(btc), normalizeEther(10 ether, btcDecimal));
    vm.stopPrank();

    // bob deposit 100 usdc and 10 btc
    vm.startPrank(BOB);
    accountManager.deposit(address(usdc), normalizeEther(100 ether, usdcDecimal));
    accountManager.deposit(address(btc), normalizeEther(10 ether, btcDecimal));
    accountManager.deposit(address(weth), normalizeEther(10 ether, wethDecimal));
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
      subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatTokenDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateBefore.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, _debtToken);

    uint256 _treasuryFeeBefore = MockERC20(_debtToken).balanceOf(liquidationTreasury);

    // add time 1 day
    // then total debt value should increase by 0.00016921837224 * 30 = 0.0050765511672
    vm.warp(block.timestamp + 1 days);

    // set price to weth from 1 to 0.8 ether USD
    // then alice borrowing power = 40 * 0.8 * 9000 / 10000 = 28.8 ether USD
    mockOracle.setTokenPrice(address(usdc), normalizeEther(1 ether, usdDecimal));
    mockOracle.setTokenPrice(address(weth), normalizeEther(8e17, usdDecimal));
    mockOracle.setTokenPrice(address(btc), normalizeEther(10 ether, usdDecimal));

    // bob try repurchase with 15 usdc
    // eth price = 0.8 USD
    // usdc price = 1 USD
    // reward = 1%
    // repurchase fee = 1%
    // timestamp increased by 1 day, debt value should increased to 30.005076
    // fee amount = 15 * 0.01 = 0.15
    uint256 _expectedFee = normalizeEther(0.15 ether, usdcDecimal);
    vm.prank(BOB, BOB);
    liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, normalizeEther(15 ether, usdcDecimal));

    // repay value = 15 * 1 = 1 USD
    // reward amount = 15 * 1.01 = 15.15 USD
    // converted weth amount = 15.15 / 0.8 = 18.9375

    uint256 _bobUsdcBalanceAfter = usdc.balanceOf(BOB);
    uint256 _bobWethBalanceAfter = weth.balanceOf(BOB);

    // check bob balance
    assertEq(_bobUsdcBalanceBefore - _bobUsdcBalanceAfter, normalizeEther(15 ether, usdcDecimal)); // pay 15 usdc
    assertEq(_bobWethBalanceAfter - _bobWethBalanceBefore, normalizeEther(18.9375 ether, wethDecimal)); // get 18.9375 weth

    CacheState memory _stateAfter = CacheState({
      collat: viewFacet.getTotalCollat(_collatToken),
      subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatTokenDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, _debtToken);

    // check state
    // note: before repurchase state should be like these
    // collat amount should be = 40
    // collat debt value should be = 30.005076 (0.0050765511672 is fixed interest increased)
    // collat debt share should be = 30
    // then after repurchase
    // collat amount should be = 40 - (_collatAmountOut) = 40 - 18.9375 = 21.0625
    // actual repaid debt amount = _repayAmount - fee = 15 - 0.15 = 14.85
    // collat debt value should be = 30.005076 - (actual repaid debt amount) = 30.005076 - 14.85 = 15.155076
    // _repayShare = actual repaid debt amount * totalDebtShare / totalDebtValue = 14.85 * 30 / 30.005076 = 14.847487
    // collat debt share should be = 30 - (_repayShare) = 30 - 14.847487 = 15.152513
    assertEq(_stateAfter.collat, normalizeEther(21.0625 ether, wethDecimal));
    assertEq(_stateAfter.subAccountCollat, normalizeEther(21.0625 ether, wethDecimal));
    assertEq(_stateAfter.debtValue, normalizeEther(15.155076 ether, usdcDecimal));
    assertEq(_stateAfter.debtShare, normalizeEther(15.152513 ether, usdcDecimal));
    assertEq(_stateAfter.subAccountDebtShare, normalizeEther(15.152513 ether, usdcDecimal));
    // globalDebt should equal to debtValue since there is only 1 position
    assertEq(viewFacet.getGlobalDebtValue(_debtToken), normalizeEther(15.155076 ether, usdcDecimal));
    vm.stopPrank();

    assertEq(MockERC20(_debtToken).balanceOf(liquidationTreasury) - _treasuryFeeBefore, _expectedFee);

    // debt token in MiniFL should be equal to debtShare after repurchased (withdrawn & burned)
    // since debt token is minted only one time, so the totalSupply should be equal to _stateAfter.debtShare after burned
    address _miniFLDebtToken = viewFacet.getDebtTokenFromToken(_debtToken);
    uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(_miniFLDebtToken);
    assertEq(_miniFL.getUserTotalAmountOf(_poolId, ALICE), _stateAfter.debtShare);
    assertEq(DebtToken(_miniFLDebtToken).totalSupply(), _stateAfter.debtShare);
  }

  function testCorrectness_ShouldRepurchasePassedWithMoreThan50PercentOfDebtToken_TransferTokenCorrectly() external {
    // alice add more collateral
    vm.startPrank(ALICE);
    accountManager.addCollateralFor(ALICE, 0, address(weth), normalizeEther(40 ether, wethDecimal));
    // alice borrow more btc token as 30% of vault = 3 btc
    accountManager.borrow(0, address(btc), normalizeEther(3 ether, btcDecimal));
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
      subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatTokenDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateBefore.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, _debtToken);

    uint256 _treasuryFeeBefore = MockERC20(_debtToken).balanceOf(liquidationTreasury);

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
    uint256 _expectedFee = normalizeEther(0.2 ether, usdcDecimal);
    vm.prank(BOB, BOB);
    liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, normalizeEther(20 ether, usdcDecimal));

    // repay value = 20 * 1 = 1 USD
    // reward amount = 20 * 1.01 = 20.20 USD
    // converted weth amount = 20.20 / 0.8 = 25.25
    // fee amount = 20 * 0.01 = 0.2 ether

    uint256 _bobUsdcBalanceAfter = usdc.balanceOf(BOB);
    uint256 _bobWethBalanceAfter = weth.balanceOf(BOB);

    // check bob balance
    assertEq(_bobUsdcBalanceBefore - _bobUsdcBalanceAfter, normalizeEther(20 ether, usdcDecimal)); // pay 20 usdc
    assertEq(_bobWethBalanceAfter - _bobWethBalanceBefore, normalizeEther(25.25 ether, wethDecimal)); // get 25.25 weth

    CacheState memory _stateAfter = CacheState({
      collat: viewFacet.getTotalCollat(_collatToken),
      subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatTokenDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, _debtToken);

    // check state
    // note: before repurchase state should be like these
    // collat amount should be = 80 on weth
    // collat debt value should be | usdc: 30.005076 | btc: 3.00050765511672 | after accure interest
    // collat debt share should be | usdc: 30 | btc: 3 |
    // then after repurchase
    // collat amount should be = 80 - (_collatAmountOut) = 80 - 25.25 = 54.75
    // actual repaid debt amount = (_repayAmount - fee) = 20 - 0.2 = 19.8
    // collat debt value should be = 30.005076 - (actual repaid debt amount) = 30.005076 - 19.8 = 10.205076
    // _repayShare = (actual repaid debt amount) * totalDebtShare / totalDebtValue = 19.8 * 30 / 30.005076 = 19.796650
    // collat debt share should be = 30 - (_repayShare) = 30 - 19.796650 = 10.203350
    assertEq(_stateAfter.collat, normalizeEther(54.75 ether, wethDecimal));
    assertEq(_stateAfter.subAccountCollat, normalizeEther(54.75 ether, wethDecimal));
    assertEq(_stateAfter.debtValue, normalizeEther(10.205076 ether, usdcDecimal));
    assertEq(_stateAfter.debtShare, normalizeEther(10.203350 ether, usdcDecimal));
    assertEq(_stateAfter.subAccountDebtShare, normalizeEther(10.203350 ether, usdcDecimal));

    // check state for btc should not be changed
    CacheState memory _btcState = CacheState({
      collat: viewFacet.getTotalCollat(address(btc)),
      subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, address(btc)),
      debtShare: viewFacet.getOverCollatTokenDebtShares(address(btc)),
      debtValue: viewFacet.getOverCollatTokenDebtValue(address(btc)),
      subAccountDebtShare: 0
    });
    (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, address(btc));
    assertEq(_btcState.collat, 0);
    assertEq(_btcState.subAccountCollat, 0);
    assertEq(_btcState.debtValue, normalizeEther(3.00050765511672 ether, btcDecimal));
    assertEq(_btcState.debtShare, normalizeEther(3 ether, btcDecimal));

    assertEq(MockERC20(_debtToken).balanceOf(liquidationTreasury) - _treasuryFeeBefore, _expectedFee);

    // debt token in MiniFL should be equal to debtShare after repurchased (withdrawn & burned)
    // since debt token is minted only one time, so the totalSupply should be equal to _stateAfter.debtShare after burned
    address _miniFLDebtToken = viewFacet.getDebtTokenFromToken(_debtToken);
    uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(_miniFLDebtToken);
    assertEq(_miniFL.getUserTotalAmountOf(_poolId, ALICE), _stateAfter.debtShare);
    assertEq(DebtToken(_miniFLDebtToken).totalSupply(), _stateAfter.debtShare);
  }

  function testCorrectness_ShouldRepurchasePassedWithMoreThanDebtTokenAmount_TransferTokenCorrectly() external {
    // alice add more collateral
    vm.startPrank(ALICE);
    accountManager.addCollateralFor(ALICE, 0, address(weth), normalizeEther(60 ether, wethDecimal));
    // alice borrow more btc token as 50% of vault = 5 btc
    accountManager.borrow(0, address(btc), normalizeEther(5 ether, btcDecimal));
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
      subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatTokenDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateBefore.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, _debtToken);

    uint256 _treasuryFeeBefore = MockERC20(_debtToken).balanceOf(liquidationTreasury);

    // set price to weth from 1 to 0.8 ether USD
    // then alice borrowing power = 80 * 0.8 * 9000 / 10000 = 57.6 ether USD

    mockOracle.setTokenPrice(address(weth), 8e17);

    // add time 1 day
    // 0.00016921837224 is interest rate per day of (30% condition slope)
    // 0.0002820306204288 is interest rate per day of (50% condition slope)
    // then total debt value of usdc should increase by 0.00016921837224 * 30 = 0.005076
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
    // timestamp increased by 1 day, usdc debt value should increased to 30.005076
    // timestamp increased by 1 day, btc value should increased to 5.001410153102144
    vm.prank(BOB, BOB);
    liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, normalizeEther(40 ether, usdcDecimal));

    // alice just have usdc debt 30.005076 (with interest)
    // when repay amount (40) > _debtValue + fee (30.005076 + 0.300050) = 30.305126
    // then actual repay amount should be 30.305126
    // repay value = 30.305126 * 1 = 30.305126 USD
    // with reward amount = 30.305126 * 1.01 = 30.60817726 USD
    // converted weth amount = 30.60817726 / 0.8 = 38.260221575
    // fee amount = 30.005076 * 0.01 = 0.300050
    uint256 _expectedFee = normalizeEther(0.300050 ether, usdcDecimal);
    uint256 _bobUsdcBalanceAfter = usdc.balanceOf(BOB);
    uint256 _bobWethBalanceAfter = weth.balanceOf(BOB);

    // check bob balance
    assertEq(_bobUsdcBalanceBefore - _bobUsdcBalanceAfter, normalizeEther(30.305126 ether, usdcDecimal)); // pay 30.305126
    assertEq(_bobWethBalanceAfter - _bobWethBalanceBefore, normalizeEther(38.260221575 ether, wethDecimal)); // get 38.260221575 weth

    CacheState memory _stateAfter = CacheState({
      collat: viewFacet.getTotalCollat(_collatToken),
      subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatTokenDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, _debtToken);

    // check state
    // note: before repurchase state should be like these
    // collat amount should be = 100 on weth
    // collat debt value should be | usdc: 30.005076 | btc: 5.001410153102144 | after accure interest
    // collat debt share should be | usdc: 30 | btc: 5 |
    // then after repurchase
    // collat amount should be = 100 - (_collatAmountOut) = 100 - 38.260221575 = 61.739778425
    // actual repaid debt amount = (_repayAmount - fee) = 30.305126 - 0.300050 = 30.005076
    // collat debt value should be = 30.005076 - (actual repaid debt amount) = 30.005076 - 30.005076 = 0
    // _repayShare = actual repaid debt amount * totalDebtShare / totalDebtValue = 30.005076 * 30 / 30.005076 = 30
    // collat debt share should be = 30 - (_repayShare) = 30 - 30 = 0
    assertEq(_stateAfter.collat, normalizeEther(61.739778425 ether, wethDecimal));
    assertEq(_stateAfter.subAccountCollat, normalizeEther(61.739778425 ether, wethDecimal));
    assertEq(_stateAfter.debtValue, 0);
    assertEq(_stateAfter.debtShare, 0);
    assertEq(_stateAfter.subAccountDebtShare, 0);

    // check state for btc should not be changed
    CacheState memory _btcState = CacheState({
      collat: viewFacet.getTotalCollat(address(btc)),
      subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, address(btc)),
      debtShare: viewFacet.getOverCollatTokenDebtShares(address(btc)),
      debtValue: viewFacet.getOverCollatTokenDebtValue(address(btc)),
      subAccountDebtShare: 0
    });
    (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, address(btc));
    assertEq(_btcState.collat, 0);
    assertEq(_btcState.subAccountCollat, 0);
    assertEq(_btcState.debtValue, normalizeEther(5.001410153102144 ether, btcDecimal));
    assertEq(_btcState.debtShare, normalizeEther(5 ether, btcDecimal));

    assertEq(MockERC20(_debtToken).balanceOf(liquidationTreasury) - _treasuryFeeBefore, _expectedFee);

    // debt token in MiniFL should be equal to debtShare after repurchased (withdrawn & burned)
    // since debt token is minted only one time, so the totalSupply should be equal to _stateAfter.debtShare after burned
    address _miniFLDebtToken = viewFacet.getDebtTokenFromToken(_debtToken);
    uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(_miniFLDebtToken);
    assertEq(_miniFL.getUserTotalAmountOf(_poolId, ALICE), _stateAfter.debtShare);
    assertEq(DebtToken(_miniFLDebtToken).totalSupply(), _stateAfter.debtShare);
  }

  function testRevert_ShouldRevertIfSubAccountIsHealthy() external {
    // criteria
    address _debtToken = address(usdc);
    address _collatToken = address(weth);

    address[] memory repurchaserOk = new address[](1);
    repurchaserOk[0] = BOB;

    adminFacet.setRepurchasersOk(repurchaserOk, true);

    vm.prank(BOB);
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Healthy.selector));
    // bob try repurchase with 2 usdc
    liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, normalizeEther(2 ether, usdcDecimal));

    // case borrowingPower == usedBorrowingPower
    // borrow more to increase usedBorrowingPower to be equal to totalBorrowingPower
    // ALICE borrow 32.4 usdc convert to usedBorrowingPower = 32.4 * 10000 / 9000 = 36 USD
    vm.prank(ALICE);
    accountManager.borrow(0, address(usdc), normalizeEther(2.4 ether, usdcDecimal));

    vm.prank(BOB);
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Healthy.selector));
    liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, normalizeEther(2 ether, usdcDecimal));
  }

  function testRevert_ShouldRevertRepurchaserIsNotOK() external {
    // criteria
    address _debtToken = address(usdc);
    address _collatToken = address(weth);

    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_Unauthorized.selector));
    // bob try repurchase with 2 usdc
    liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, normalizeEther(2 ether, usdcDecimal));
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
      subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatTokenDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateBefore.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, _debtToken);

    // add time 1 day
    // then total debt value should increase by 0.00016921837224 * 30 = 0.0050765511672
    vm.warp(block.timestamp + 1 days + 1);

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
    vm.startPrank(BOB, BOB);
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_RepayAmountExceedThreshold.selector));
    // bob try repurchase with 20 usdc but borrowed value is 30.0050765511672 / 2 = 15.0025382755836,
    // so bob can't pay more than 15.0025382755836 followed by condition (!> 50% of borrowed value)
    liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, normalizeEther(20 ether, usdcDecimal));
    vm.stopPrank();
  }

  function testRevert_ShouldRevertIfInsufficientCollateralAmount() external {
    vm.startPrank(ALICE);
    // alice has 36 ether USD power from eth
    // alice add more collateral in other assets
    // then borrowing power will be increased by 100 * 10 * 9000 / 10000 = 900 ether USD
    // total borrowing power is 936 ether USD
    accountManager.addCollateralFor(ALICE, 0, address(btc), normalizeEther(100 ether, btcDecimal));
    // alice borrow more usdc token more 50% of vault = 50 usdc
    // alice used borrowed value is ~80
    accountManager.borrow(0, address(usdc), normalizeEther(50 ether, usdcDecimal));
    vm.stopPrank();

    // criteria
    address _debtToken = address(usdc);
    address _collatToken = address(weth);

    // add time 1 day
    // 0.0004512489926688 is interest rate per day of (80% condition slope)
    // then total debt value of usdc should increase by 0.0004512489926688 * 80 = 0.036099919413504
    vm.warp(block.timestamp + 1 days + 1);

    // set price to btc from 10 to 0.1 ether USD
    // then alice borrowing power from btc = 100 * 0.1 * 9000 / 10000 = 9 ether USD
    // total borrowing power is 36 + 9 = 45 ether USD
    mockOracle.setTokenPrice(address(btc), normalizeEther(1e17, usdDecimal));
    mockOracle.setTokenPrice(address(weth), normalizeEther(1e18, usdDecimal));
    mockOracle.setTokenPrice(address(usdc), normalizeEther(1e18, usdDecimal));

    // bob try repurchase with 40 usdc
    // eth price = 0.2 USD
    // usdc price = 1 USD
    // reward = 0.01%
    // timestamp increased by 1 day, usdc debt value should increased to 80.036099919413504
    vm.startPrank(BOB, BOB);

    // repay value = 40 * 1 = 40 USD
    // reward amount = 40 * 1.01 = 40.40 USD
    // converted weth amount = 40.40 / 1 = 40.40
    // should revert because alice has eth collat just 40
    vm.expectRevert(abi.encodeWithSelector(ILiquidationFacet.LiquidationFacet_InsufficientAmount.selector));
    liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, normalizeEther(40 ether, usdcDecimal));
    vm.stopPrank();
  }

  function testCorrectness_WhenRepurchaseWithRepayTokenAndCollatTokenAreSameToken_TransferTokenCorrectly() external {
    vm.startPrank(ALICE);
    accountManager.addCollateralFor(ALICE, 0, address(usdc), normalizeEther(20 ether, usdcDecimal));

    accountManager.borrow(0, address(usdc), normalizeEther(10 ether, usdcDecimal));
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
      subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatTokenDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateBefore.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, _debtToken);

    uint256 _treasuryFeeBefore = MockERC20(_debtToken).balanceOf(liquidationTreasury);

    // add time 1 day
    // then total debt value should increase by 0.000225624496291200 * 40 = 0.009024979851648
    vm.warp(block.timestamp + 1 days);

    // set price to weth from 1 to 0.6 ether USD
    // then alice borrowing power (weth) = 40 * 0.6 * 9000 / 10000 = 21.6 ether USD
    // then alice borrowing power (usdc) = 20 * 1 * 9000 / 10000 = 18 ether USD
    // total = 28.8 + 18 = 46.8 ether USD
    mockOracle.setTokenPrice(address(usdc), normalizeEther(1 ether, usdDecimal));
    mockOracle.setTokenPrice(address(weth), normalizeEther(6e17, usdDecimal));
    mockOracle.setTokenPrice(address(btc), normalizeEther(10 ether, usdDecimal));

    // bob try repurchase with 15 usdc
    // eth price = 0.6 USD
    // usdc price = 1 USD
    // reward = 1%
    // repurchase fee = 1%
    // timestamp increased by 1 day, debt value should increased to 30.009024979851648
    // fee amount = 15 * 0.01 = 0.15
    uint256 _expectedFee = normalizeEther(0.15 ether, usdcDecimal);
    vm.prank(BOB, BOB);
    liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, normalizeEther(15 ether, usdcDecimal));

    // repay value = 15 * 1 = 1 USD
    // reward amount = 15 * 1.01 = 15.15 USD
    // converted usdc amount = 15.15 / 1 = 15.15 ether

    uint256 _bobUsdcBalanceAfter = usdc.balanceOf(BOB);

    // check bob balance
    assertEq(_bobUsdcBalanceAfter - _bobUsdcBalanceBefore, _expectedFee); // pay 15 usdc and get reward 15.15 usdc

    CacheState memory _stateAfter = CacheState({
      collat: viewFacet.getTotalCollat(_collatToken),
      subAccountCollat: viewFacet.getCollatAmountOf(ALICE, subAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatTokenDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatDebtShareAndAmountOf(ALICE, 0, _debtToken);

    // check state
    // note: before repurchase state should be like these
    // collat amount (usdc) should be = 20
    // collat debt value should be = 40.009024 (0.009024979851648 is fixed interest increased)
    // collat debt share should be = 40
    // then after repurchase
    // collat amount should be = 20 - (_collatAmountOut) = 20 - 15.15 = 4.85
    // actual repaid debt amount = _repayAmount - fee = 15 - 0.15 = 14.85
    // collat debt value should be = 40.009024 - (actual repaid debt amount) = 40.009024 - 14.85 = 25.159024
    // _repayShare = actual repaid debt amount * totalDebtShare / totalDebtValue = 14.85 * 40 / 40.009024 = 14.846650
    // collat debt share should be = 40 - (_repayShare) = 40 - 14.846650 = 25.15335
    assertEq(_stateAfter.collat, normalizeEther(4.85 ether, usdcDecimal));
    assertEq(_stateAfter.subAccountCollat, normalizeEther(4.85 ether, usdcDecimal));
    assertEq(_stateAfter.debtValue, normalizeEther(25.159024 ether, usdcDecimal));
    assertEq(_stateAfter.debtShare, normalizeEther(25.15335 ether, usdcDecimal));
    assertEq(_stateAfter.subAccountDebtShare, normalizeEther(25.15335 ether, usdcDecimal));
    // globalDebt should equal to debtValue since there is only 1 position
    assertEq(viewFacet.getGlobalDebtValue(_debtToken), normalizeEther(25.159024 ether, usdcDecimal));

    assertEq(MockERC20(_debtToken).balanceOf(liquidationTreasury) - _treasuryFeeBefore, _expectedFee);

    // debt token in MiniFL should be equal to debtShare after repurchased (withdrawn & burned)
    // since debt token is minted only one time, so the totalSupply should be equal to _stateAfter.debtShare after burned
    address _miniFLDebtToken = viewFacet.getDebtTokenFromToken(_debtToken);
    uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(_miniFLDebtToken);
    assertEq(_miniFL.getUserTotalAmountOf(_poolId, ALICE), _stateAfter.debtShare);
    assertEq(DebtToken(_miniFLDebtToken).totalSupply(), _stateAfter.debtShare);
  }

  // TODO: fix test case
  // function testWrongRepurchase() public {
  //   // reset ALICE state from setUp
  //   vm.startPrank(ALICE);
  //   accountManager.repayFor(
  //     ALICE,
  //     subAccount0,
  //     address(usdc),
  //     normalizeEther(30 ether, usdcDecimal),
  //     normalizeEther(30 ether, usdcDecimal)
  //   );
  //   accountManager.removeCollateral(subAccount0, address(weth), 40 ether);

  //   mockOracle.setTokenPrice(address(weth), 1 ether);
  //   accountManager.addCollateralFor(ALICE, subAccount0, address(usdc), normalizeEther(2 ether, usdcDecimal));
  //   accountManager.borrow(subAccount0, address(weth), 1 ether);
  //   vm.stopPrank();

  //   adminFacet.setFees(0, 1000, 100, 5000);
  //   adminFacet.setLiquidationParams(10000, 10000);

  //   mockOracle.setTokenPrice(address(weth), 2 ether);
  //   vm.startPrank(BOB);
  //   liquidationFacet.repurchase(ALICE, subAccount0, address(weth), address(usdc), 1.2 ether);
  // }
}
