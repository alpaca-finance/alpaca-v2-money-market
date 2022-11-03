// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, console } from "./MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { IBorrowFacet, LibDoublyLinkedList } from "../../contracts/money-market/facets/BorrowFacet.sol";
import { IRepurchaseFacet } from "../../contracts/money-market/facets/RepurchaseFacet.sol";
import { IAdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";
import { TripleSlopeModel6, IInterestRateModel } from "../../contracts/money-market/interest-models/TripleSlopeModel6.sol";

// utils
import { console } from "../utils/console.sol";

struct CacheState {
  uint256 collat;
  uint256 subAccountCollat;
  uint256 debtShare;
  uint256 debtValue;
  uint256 subAccountDebtShare;
}

contract MoneyMarket_BorrowFacetTest is MoneyMarket_BaseTest {
  using LibDoublyLinkedList for LibDoublyLinkedList.List;
  address _aliceSubAccount0 = LibMoneyMarket01.getSubAccount(ALICE, 0);

  function setUp() public override {
    super.setUp();

    TripleSlopeModel6 tripleSlope6 = new TripleSlopeModel6();
    adminFacet.setInterestModel(address(weth), address(tripleSlope6));
    adminFacet.setInterestModel(address(btc), address(tripleSlope6));
    adminFacet.setInterestModel(address(usdc), address(tripleSlope6));

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
      collat: collateralFacet.collats(_collatToken),
      subAccountCollat: collateralFacet.subAccountCollats(_aliceSubAccount0, _collatToken),
      debtShare: borrowFacet.debtShares(_debtToken),
      debtValue: borrowFacet.debtValues(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateBefore.subAccountDebtShare, ) = borrowFacet.getDebt(ALICE, 0, _debtToken);

    // set price to weth from 1 to 0.8 ether USD
    // then alice borrowing power = 40 * 0.8 * 9000 / 10000 = 28.8 ether USD
    oracle.setPrice(address(weth), 8e17);

    // add time 1 day
    // then total debt value should increase by 0.00016921837224 * 30 = 0.0050765511672
    vm.warp(1 days + 1);

    // bob try repurchase with 15 usdc
    // eth price = 0.8 USD
    // usdc price = 1 USD
    // reward = 0.01%
    // timestamp increased by 1 day, debt value should increased to 30.0050765511672
    vm.prank(BOB);
    repurchaseFacet.repurchase(_aliceSubAccount0, _debtToken, _collatToken, 15 ether);

    // repay value = 15 * 1 = 1 USD
    // reward amount = 15 * 1.01 = 15.15 USD
    // converted weth amount = 15.15 / 0.8 = 18.9375

    uint256 _bobUsdcBalanceAfter = usdc.balanceOf(BOB);
    uint256 _bobWethBalanceAfter = weth.balanceOf(BOB);

    // check bob balance
    assertEq(_bobUsdcBalanceBefore - _bobUsdcBalanceAfter, 15 ether); // pay 15 usdc
    assertEq(_bobWethBalanceAfter - _bobWethBalanceBefore, 18.9375 ether); // get 18.9375 weth

    CacheState memory _stateAfter = CacheState({
      collat: collateralFacet.collats(_collatToken),
      subAccountCollat: collateralFacet.subAccountCollats(_aliceSubAccount0, _collatToken),
      debtShare: borrowFacet.debtShares(_debtToken),
      debtValue: borrowFacet.debtValues(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateAfter.subAccountDebtShare, ) = borrowFacet.getDebt(ALICE, 0, _debtToken);

    // check state
    // note: before repurchase state should be like these
    // collat amount should be = 40
    // collat debt value should be = 30.0050765511672 (0.0050765511672 is fixed interest increased)
    // collat debt share should be = 30
    // then after repurchase
    // collat amount should be = 40 - (_collatAmountOut) = 40 - 18.9375 = 21.0625
    // collat debt value should be = 30.0050765511672 - (_repayAmount) = 30.0050765511672 - 15 = 15.0050765511672
    // _repayShare = _repayAmount * totalDebtShare / totalDebtValue = 15 * 30 / 30.0050765511672 = 14.997462153866591690
    // collat debt share should be = 30 - (_repayShare) = 30 - 14.997462153866591690 = 15.00253784613340831
    assertEq(_stateAfter.collat, 21.0625 ether);
    assertEq(_stateAfter.subAccountCollat, 21.0625 ether);
    assertEq(_stateAfter.debtValue, 15.0050765511672 ether);
    assertEq(_stateAfter.debtShare, 15.00253784613340831 ether);
    assertEq(_stateAfter.subAccountDebtShare, 15.00253784613340831 ether);
    vm.stopPrank();
  }

  function testRevert_shouldRevertIfSubAccountIsHealthy() external {
    // criteria
    address _debtToken = address(usdc);
    address _collatToken = address(weth);

    vm.startPrank(BOB);
    vm.expectRevert(abi.encodeWithSelector(IRepurchaseFacet.RepurchaseFacet_Healthy.selector));
    // bob try repurchase with 2 usdc
    repurchaseFacet.repurchase(_aliceSubAccount0, _debtToken, _collatToken, 2 ether);
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
      collat: collateralFacet.collats(_collatToken),
      subAccountCollat: collateralFacet.subAccountCollats(_aliceSubAccount0, _collatToken),
      debtShare: borrowFacet.debtShares(_debtToken),
      debtValue: borrowFacet.debtValues(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateBefore.subAccountDebtShare, ) = borrowFacet.getDebt(ALICE, 0, _debtToken);

    // set price to weth from 1 to 0.8 ether USD
    // then alice borrowing power = 40 * 0.8 * 9000 / 10000 = 28.8 ether USD
    oracle.setPrice(address(weth), 8e17);

    // add time 1 day
    // then total debt value should increase by 0.00016921837224 * 30 = 0.0050765511672
    vm.warp(1 days + 1);

    // bob try repurchase with 2 usdc
    // eth price = 0.8 USD
    // usdc price = 1 USD
    // reward = 0.01%
    // timestamp increased by 1 day, debt value should increased to 30.0050765511672
    vm.startPrank(BOB);
    vm.expectRevert(abi.encodeWithSelector(IRepurchaseFacet.RepurchaseFacet_RepayDebtValueTooHigh.selector));
    // bob try repurchase with 20 usdc but borrowed value is 30.0050765511672 / 2 = 15.0025382755836,
    // so bob can't pay more than 15.0025382755836 followed by condition (!> 50% of borrowed value)
    repurchaseFacet.repurchase(_aliceSubAccount0, _debtToken, _collatToken, 20 ether);
    vm.stopPrank();
  }
}
