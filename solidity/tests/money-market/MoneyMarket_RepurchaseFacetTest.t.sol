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
    collateralFacet.addCollateral(ALICE, 0, address(weth), 5 ether);
    // alice added collat 5 ether
    // given collateralFactor = 9000, weth price = 1
    // then alice got power = 5 * 1 * 9000 / 10000 = 4.5 ether USD
    borrowFacet.borrow(0, address(usdc), 4 ether);
    vm.stopPrank();
  }

  function testCorrectness_shouldRepurchaseWithSingleAssetCorrectly() external {
    // criteria
    address _aliceSubAccount = LibMoneyMarket01.getSubAccount(ALICE, 0);
    address _debtToken = address(usdc);
    address _collatToken = address(weth);

    uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);
    uint256 _bobWethBalanceBefore = weth.balanceOf(BOB);

    // collat amount should be = 5
    // collat debt value should be = 4
    // collat debt share should be = 4
    CacheState memory _stateBefore = CacheState({
      collat: collateralFacet.collats(_collatToken),
      subAccountCollat: collateralFacet.subAccountCollats(_aliceSubAccount, _collatToken),
      debtShare: borrowFacet.debtShares(_debtToken),
      debtValue: borrowFacet.debtValues(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateBefore.subAccountDebtShare, ) = borrowFacet.getDebt(ALICE, 0, _debtToken);

    // set price to weth from 1 to 0.9 ether USD
    // then borrowing power should be 4.05
    oracle.setPrice(address(weth), 9e17);

    // warp timestamp to 2 from 1
    // then total debt value should increase by 0.1
    vm.warp(2);

    // bob try repurchase with 2 usdc
    // eth price = 0.9 USD
    // usdc price = 1 USD
    // reward = 0.01%
    // timestamp increased by 1, debt value should increased to 4.1
    vm.prank(BOB);
    repurchaseFacet.repurchase(_aliceSubAccount, _debtToken, _collatToken, 2 ether);

    uint256 _bobUsdcBalanceAfter = usdc.balanceOf(BOB);
    uint256 _bobWethBalanceAfter = weth.balanceOf(BOB);

    // check bob balance
    assertEq(_bobUsdcBalanceBefore - _bobUsdcBalanceAfter, 2 ether); // pay 2 usdc
    assertEq(_bobWethBalanceAfter - _bobWethBalanceBefore, 2.244444444444444444 ether); // get 2.244444444444444444 weth

    CacheState memory _stateAfter = CacheState({
      collat: collateralFacet.collats(_collatToken),
      subAccountCollat: collateralFacet.subAccountCollats(_aliceSubAccount, _collatToken),
      debtShare: borrowFacet.debtShares(_debtToken),
      debtValue: borrowFacet.debtValues(_debtToken),
      subAccountDebtShare: 0
    });
    (_stateAfter.subAccountDebtShare, ) = borrowFacet.getDebt(ALICE, 0, _debtToken);

    // check state
    // note: before repurchase state should be like these
    // collat amount should be = 5
    // collat debt value should be = 4.1 (0.1 is fixed interest increased)
    // collat debt share should be = 4
    // then after repurchase
    // collat amount should be = 5 - (_collatAmountOut) = 5 - 2.244444444444444444 = 2.755555555555555556
    // collat debt value should be = 4.1 - (_repayAmount) = 4.1 - 2 = 2.1
    // _repayShare = _repayAmount * totalDebtShare / totalDebtValue = 2 * 4 / 4.1 = 1.951219512195121951
    // collat debt share should be = 4 - (_repayShare) = 4 - 1.951219512195121951 = 2.048780487804878049
    assertEq(_stateAfter.collat, 2.755555555555555556 ether);
    assertEq(_stateAfter.subAccountCollat, 2.755555555555555556 ether);
    assertEq(_stateAfter.debtValue, 2.1 ether);
    assertEq(_stateAfter.debtShare, 2.048780487804878049 ether);
    assertEq(_stateAfter.subAccountDebtShare, 2.048780487804878049 ether);
    vm.stopPrank();
  }
}
