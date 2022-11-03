// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, console } from "./MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { IBorrowFacet, LibDoublyLinkedList } from "../../contracts/money-market/facets/BorrowFacet.sol";
import { IAdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";
import { FixedInterestRateModel, IInterestRateModel } from "../../contracts/money-market/interest-model/FixedInterestRateModel.sol";

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

  function setUp() public override {
    super.setUp();

    FixedInterestRateModel model = new FixedInterestRateModel();
    adminFacet.setInterestModel(address(weth), address(model));
    adminFacet.setInterestModel(address(usdc), address(model));

    // bob deposit 100 usdc
    vm.prank(BOB);
    lendFacet.deposit(address(usdc), 100 ether);

    vm.startPrank(ALICE);
    // alice add collat 5 ether
    // given collateralFactor = 9000, weth price = 1
    // then alice got power = 5 * 1 * 9000 / 10000 = 4.5 ether USD
    collateralFacet.addCollateral(ALICE, 0, address(weth), 5 ether);

    // alice borrow usdc at maximum
    // given borrowFactor = 1000, weth price = 1
    // maximumBorrowedUSDValue = 4.5 ether USD
    // maximumBorrowed weth amount = 4.5 * 10000 / (10000 + 1000) ~ 4.090909090909090909
    // _borrowedUSDValue = 4.090909090909090909 * (10000 + 1000) / 10000 = 4.5 ether USD
    borrowFacet.borrow(0, address(usdc), 4.090909090909090909 ether);
    vm.stopPrank();
  }

  // test 1 asset collat & debt
  // test multiple assets collat & debt

  function testCorrectness_shouldRepurchaseWithSingleAssetCorrectly() external {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage mmStorage = LibMoneyMarket01.moneyMarketDiamondStorage();

    // criteria
    address _aliceSubAccount = LibMoneyMarket01.getSubAccount(ALICE, 0);
    address _debtToken = address(usdc);
    address _collatToken = address(weth);

    uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);
    uint256 _bobWethBalanceBefore = weth.balanceOf(BOB);

    // given usdc price = 1, eth price = 1
    // alice added collat = 5 ether
    // then collats[weth] = 5, subAccountCollats[weth] = 5
    // and alice borrowed 4.090909090909090909
    // then debtShares[usdc], debtValues[usdc] and subAccountDebtShares[usdc] = 4.090909090909090909
    CacheState memory _stateBefore = CacheState({
      collat: collateralFacet.collats(_collatToken),
      subAccountCollat: collateralFacet.subAccountCollats(_aliceSubAccount, _collatToken),
      debtShare: borrowFacet.debtShares(_debtToken),
      debtValue: borrowFacet.debtValues(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateBefore.subAccountDebtShare, ) = borrowFacet.getDebt(ALICE, 0, _debtToken);

    // set price to decrease borrowing power
    // alice power before decrease price is 4.5 usd
    // weth price change from 1 USD to 0.9 USD
    // alice power after decrease price is 4.05 usd (5 * 0.9 * 9000 / 10000)
    oracle.setPrice(address(weth), 9e17);

    // warp timestamp to 2 from 1
    // then total debt value should increase by 0.1
    vm.warp(2);
    uint256 _accuredInterest = 1e17;

    // bob try repurchase with 2 usdc
    // eth price = 0.9 USD
    // usdc price = 1 USD
    // reward = 0.01%
    // repay value = 2 * 1 = 2 USD
    // value with reward = 2 + (2 * 100 / 10000) = 2.02 USD
    // expect ETH = 2.02 / 0.9 = 2.244444444444444444
    // collateral should decreased by 2.244444444444444444
    // debt value should decreased by 2 but
    // debt share should decreased by (debt value * total supply / total value)
    // then 2 * 4.090909090909090909 / 4.190909090909090909 = 1.952277657266811279
    vm.prank(BOB);
    repurchaseFacet.repurchase(_aliceSubAccount, _debtToken, _collatToken, 2 ether);

    uint256 _bobUsdcBalanceAfter = usdc.balanceOf(BOB);
    uint256 _bobWethBalanceAfter = weth.balanceOf(BOB);

    CacheState memory _stateAfter = CacheState({
      collat: collateralFacet.collats(_collatToken),
      subAccountCollat: collateralFacet.subAccountCollats(_aliceSubAccount, _collatToken),
      debtShare: borrowFacet.debtShares(_debtToken),
      debtValue: borrowFacet.debtValues(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateAfter.subAccountDebtShare, ) = borrowFacet.getDebt(ALICE, 0, _debtToken);

    // check bob balance
    assertEq(_bobUsdcBalanceBefore - _bobUsdcBalanceAfter, 2 ether);
    assertEq(_bobWethBalanceAfter - _bobWethBalanceBefore, 2.244444444444444444 ether);

    // check state
    assertEq(_stateBefore.collat - _stateAfter.collat, 2.244444444444444444 ether);
    assertEq(_stateBefore.subAccountCollat - _stateAfter.subAccountCollat, 2.244444444444444444 ether);
    assertEq(_stateBefore.debtShare - _stateAfter.debtShare, 1.952277657266811279 ether);
    assertEq(_stateBefore.debtValue + _accuredInterest - _stateAfter.debtValue, 2 ether);
    assertEq(_stateBefore.subAccountDebtShare - _stateAfter.subAccountDebtShare, 1.952277657266811279 ether);
    vm.stopPrank();
  }
}
