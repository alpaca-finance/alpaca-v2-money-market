// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, console } from "./MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { TripleSlopeModel6, IInterestRateModel } from "../../contracts/money-market/interest-models/TripleSlopeModel6.sol";
import { FixedFeeModel, IFeeModel } from "../../contracts/money-market/fee-models/FixedFeeModel.sol";

struct CacheState {
  uint256 collat;
  uint256 subAccountCollat;
  uint256 debtShare;
  uint256 debtValue;
  uint256 subAccountDebtShare;
}

contract MoneyMarket_Liquidation_IbRepurchaseTest is MoneyMarket_BaseTest {
  uint256 _subAccountId = 0;
  address _aliceSubAccount0 = LibMoneyMarket01.getSubAccount(ALICE, _subAccountId);

  function setUp() public override {
    super.setUp();

    TripleSlopeModel6 tripleSlope6 = new TripleSlopeModel6();
    adminFacet.setInterestModel(address(weth), address(tripleSlope6));
    adminFacet.setInterestModel(address(btc), address(tripleSlope6));
    adminFacet.setInterestModel(address(usdc), address(tripleSlope6));

    FixedFeeModel fixedFeeModel = new FixedFeeModel();
    adminFacet.setRepurchaseRewardModel(fixedFeeModel);

    vm.startPrank(DEPLOYER);
    mockOracle.setTokenPrice(address(btc), 10 ether);
    vm.stopPrank();

    // bob deposit 100 usdc and 10 btc
    vm.startPrank(BOB);
    lendFacet.deposit(address(usdc), normalizeEther(100 ether, usdcDecimal));
    lendFacet.deposit(address(btc), normalizeEther(10 ether, btcDecimal));
    vm.stopPrank();

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, 0, address(weth), normalizeEther(40 ether, wethDecimal));
    // alice added collat 40 ether
    // given collateralFactor = 9000, weth price = 1
    // then alice got power = 40 * 1 * 9000 / 10000 = 36 ether USD
    // alice borrowed 30% of vault then interest should be 0.0617647058676 per year
    // interest per day = 0.00016921837224
    borrowFacet.borrow(0, address(usdc), normalizeEther(30 ether, usdcDecimal));
    vm.stopPrank();
  }

  // ib repurchase tests

  function testCorrectness_WhenRepurchaseDebtAndTakeIbTokenAsCollateral_ShouldWork() external {
    // criteria
    address _debtToken = address(usdc);
    address _collatToken = address(ibWeth);

    weth.mint(ALICE, 40 ether);
    vm.startPrank(ALICE);
    // withdraw weth and add ibWeth as collateral for simpler calculation
    lendFacet.deposit(address(weth), 40 ether);
    ibWeth.approve(moneyMarketDiamond, type(uint256).max);
    collateralFacet.addCollateral(ALICE, _subAccountId, address(ibWeth), 40 ether);
    collateralFacet.removeCollateral(_subAccountId, address(weth), 40 ether);
    vm.stopPrank();

    // now 1 ibWeth = 1 weth
    // make 1 ibWeth = 2 weth by inflating MM with 40 weth
    vm.prank(BOB);
    lendFacet.deposit(address(weth), 40 ether);
    vm.prank(moneyMarketDiamond);
    ibWeth.onWithdraw(BOB, BOB, 0, 40 ether);

    // ALICE borrow another 30 USDC = 60 USDC in debt
    vm.prank(ALICE);
    borrowFacet.borrow(0, address(usdc), 30 ether);

    uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);
    uint256 _bobIbWethBalanceBefore = ibWeth.balanceOf(BOB);

    // collat amount should be = 40 ibWEth
    // collat debt value should be = 60
    // collat debt share should be = 60
    CacheState memory _stateBefore = CacheState({
      collat: viewFacet.getTotalCollat(_collatToken),
      subAccountCollat: viewFacet.getOverCollatSubAccountCollatAmount(ALICE, subAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateBefore.subAccountDebtShare, ) = viewFacet.getOverCollatSubAccountDebt(ALICE, 0, _debtToken);

    uint256 _treasuryBalanceBefore = MockERC20(_debtToken).balanceOf(treasury);

    // add time 1 day
    // then total debt value should increase by 0.0033843674448 * 60 = 0.20306204668800000
    vm.warp(block.timestamp + 1 days);

    // set price to weth from 1 to 0.8 ether USD
    // 1 ibwETH = 2 weth, ibWeth prie = 1.6 USD
    // then alice borrowing power = 40 * 0.8 * 2 * 9000 / 10000 = 57.6 ether USD
    mockOracle.setTokenPrice(address(weth), 8e17);
    mockOracle.setTokenPrice(address(usdc), 1 ether);

    // bob try repurchase with 15 usdc
    // eth price = 0.8 USD, ibWeth price = 1.6 USD
    // usdc price = 1 USD
    // reward = 1%
    // repurchase fee = 1%
    // timestamp increased by 1 day, debt value should increased to 60.20306204668800000
    // RepuschaseFee = 15 * 0.01 = 0.15

    uint256 _expectedFeeToTreasury = 0.15 ether;
    vm.prank(BOB);
    liquidationFacet.repurchase(ALICE, _subAccountId, _debtToken, _collatToken, 15 ether);

    // repay value = 15 * 1 = 1 USD
    // reward amount = 15 * 1.01 = 15.15 USD
    // converted weth amount = 15.15 / 1.6 = 9.46875

    uint256 _bobUsdcBalanceAfter = usdc.balanceOf(BOB);
    uint256 _bobIbWethBalanceAfter = ibWeth.balanceOf(BOB);

    // // check bob balance
    assertEq(_bobUsdcBalanceBefore - _bobUsdcBalanceAfter, 15 ether); // pay 15 usdc
    assertEq(_bobIbWethBalanceAfter - _bobIbWethBalanceBefore, 9.46875 ether); // get 9.46875 weth

    CacheState memory _stateAfter = CacheState({
      collat: viewFacet.getTotalCollat(_collatToken),
      subAccountCollat: viewFacet.getOverCollatSubAccountCollatAmount(ALICE, subAccount0, _collatToken),
      debtShare: viewFacet.getOverCollatTokenDebtShares(_debtToken),
      debtValue: viewFacet.getOverCollatDebtValue(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateAfter.subAccountDebtShare, ) = viewFacet.getOverCollatSubAccountDebt(ALICE, 0, _debtToken);

    // check state
    // note: before repurchase state should be like these
    // collat amount should be = 40
    // collat debt value should be = 60.020306204668800000
    // collat debt share should be = 60
    // then after repurchase
    // collat amount should be = 40 - (_collatAmountOut) = 40 - 9.46875 = 30.53125
    // actual repaid debt amount = _repayAmount - fee = 15 - 0.15 = 14.85
    // collat debt value should be = 60.020306204668800000 - (_repayAmount) = 60.020306204668800000 - 14.85 = 45.1703062046688
    // _repayShare = _repayAmount * totalDebtShare / totalDebtValue = 14.85 * 60 / 60.020306204668800000 = 14.844975914679551842
    // collat debt share should be = 60 - (_repayShare) = 60 - 14.844975914679551842 = 45.155024085320448158
    assertEq(_stateAfter.collat, 30.53125 ether);
    assertEq(_stateAfter.subAccountCollat, 30.53125 ether);
    assertEq(_stateAfter.debtValue, 45.1703062046688 ether);
    assertEq(_stateAfter.debtShare, 45.155024085320448158 ether);
    assertEq(_stateAfter.subAccountDebtShare, 45.155024085320448158 ether);
    vm.stopPrank();
    assertEq(MockERC20(_debtToken).balanceOf(treasury) - _treasuryBalanceBefore, _expectedFeeToTreasury);
  }
}
