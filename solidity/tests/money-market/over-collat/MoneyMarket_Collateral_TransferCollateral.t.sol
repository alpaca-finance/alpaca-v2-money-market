// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20 } from "../MoneyMarket_BaseTest.t.sol";

// libraries
import { LibMoneyMarket01 } from "../../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { ICollateralFacet, LibDoublyLinkedList } from "../../../contracts/money-market/facets/CollateralFacet.sol";

contract MoneyMarket_Collateral_TransferCollateralTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenUserTransferCollateralBTWSubAccount_ShouldWork() external {
    uint256 _addCollateralAmount = 10 ether;
    uint256 _transferCollateralAmount = 1 ether;

    // alice add collateral 10 weth
    vm.prank(ALICE);
    accountManager.addCollateralFor(ALICE, subAccount0, address(weth), _addCollateralAmount);

    uint256 _MMbalanceBeforeTransfer = weth.balanceOf(moneyMarketDiamond);
    uint256 _balanceBeforeTransfer = weth.balanceOf(ALICE);
    uint256 _wethCollateralAmountBeforeTransfer = viewFacet.getTotalCollat(address(weth));

    // alice transfer collateral from subAccount0 to subAccount1
    vm.prank(ALICE);
    collateralFacet.transferCollateral(subAccount0, subAccount1, address(weth), _transferCollateralAmount);

    LibDoublyLinkedList.Node[] memory subAccount0CollatList = viewFacet.getAllSubAccountCollats(ALICE, subAccount0);

    LibDoublyLinkedList.Node[] memory subAccount1CollatList = viewFacet.getAllSubAccountCollats(ALICE, subAccount1);

    uint256 _subAccount0BorrowingPower = viewFacet.getTotalBorrowingPower(ALICE, subAccount0);

    uint256 _subAccount1BorrowingPower = viewFacet.getTotalBorrowingPower(ALICE, subAccount1);

    // validate
    // subAccount0
    assertEq(subAccount0CollatList[0].amount, 9 ether);
    // 9 ether * 9000/ 10000
    assertEq(_subAccount0BorrowingPower, 8.1 ether);
    // subAccount1
    assertEq(subAccount1CollatList[0].amount, _transferCollateralAmount);
    // 1 ether * 9000/ 10000
    assertEq(_subAccount1BorrowingPower, 0.9 ether);

    // Global states
    assertEq(weth.balanceOf(moneyMarketDiamond), _MMbalanceBeforeTransfer);
    assertEq(viewFacet.getTotalCollat(address(weth)), _wethCollateralAmountBeforeTransfer);
    assertEq(weth.balanceOf(ALICE), _balanceBeforeTransfer);
  }

  function testRevert_WhenUserTransferCollateralWithSameSubAccount_ShouldRevert() external {
    uint256 _addCollateralAmount = 10 ether;
    uint256 _transferCollateralAmount = 1 ether;

    // alice add collateral 10 weth
    vm.prank(ALICE);
    accountManager.addCollateralFor(ALICE, subAccount0, address(weth), _addCollateralAmount);

    // alice transfer collateral from subAccount0 to subAccount0
    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(ICollateralFacet.CollateralFacet_NoSelfTransfer.selector));
    collateralFacet.transferCollateral(subAccount0, subAccount0, address(weth), _transferCollateralAmount);
  }
}
