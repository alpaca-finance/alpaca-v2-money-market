// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest, MockERC20 } from "../MoneyMarket_BaseTest.t.sol";

// libraries
import { LibMoneyMarket01 } from "../../../contracts/money-market/libraries/LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "../../../contracts/money-market/libraries/LibDoublyLinkedList.sol";
// interfaces
import { IMiniFL } from "../../../contracts/money-market/interfaces/IMiniFL.sol";

contract MoneyMarket_Collateral_AddCollateralTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testRevert_WhenUserAddTooMuchToken() external {
    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, 10 ether);
    accountManager.addCollateralFor(ALICE, 0, address(weth), 10 ether);

    usdc.approve(moneyMarketDiamond, 10 ether);
    accountManager.addCollateralFor(ALICE, 0, address(usdc), normalizeEther(10 ether, usdcDecimal));

    btc.approve(moneyMarketDiamond, 10 ether);
    accountManager.addCollateralFor(ALICE, 0, address(btc), 10 ether);

    // now maximum is 3 token per account, when try add collat 4th token should revert
    cake.approve(moneyMarketDiamond, 10 ether);
    vm.expectRevert(abi.encodeWithSelector(LibMoneyMarket01.LibMoneyMarket01_NumberOfTokenExceedLimit.selector));
    accountManager.addCollateralFor(ALICE, 0, address(cake), 10 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenAddCollateral_TokenShouldTransferFromUserToMM() external {
    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, 10 ether);
    accountManager.addCollateralFor(ALICE, 0, address(weth), 10 ether);
    vm.stopPrank();

    assertEq(weth.balanceOf(ALICE), 990 ether);
    assertEq(weth.balanceOf(moneyMarketDiamond), 10 ether);
  }

  function testCorrectness_WhenUserAddMultipleCollaterals_ListShouldUpdate() external {
    uint256 _aliceWethCollatAmount = 10 ether;
    uint256 _aliceUsdcCollatAmount = normalizeEther(20 ether, usdcDecimal);

    vm.startPrank(ALICE);

    accountManager.addCollateralFor(ALICE, subAccount0, address(weth), _aliceWethCollatAmount);
    vm.stopPrank();

    LibDoublyLinkedList.Node[] memory collats = viewFacet.getAllSubAccountCollats(ALICE, subAccount0);

    assertEq(collats.length, 1);
    assertEq(collats[0].amount, _aliceWethCollatAmount);

    vm.startPrank(ALICE);

    // list will be add at the front of linkList
    accountManager.addCollateralFor(ALICE, subAccount0, address(usdc), _aliceUsdcCollatAmount);
    vm.stopPrank();

    collats = viewFacet.getAllSubAccountCollats(ALICE, subAccount0);

    assertEq(collats.length, 2);
    assertEq(collats[0].amount, _aliceUsdcCollatAmount);
    assertEq(collats[1].amount, _aliceWethCollatAmount);

    // Alice try to update weth collateral
    vm.startPrank(ALICE);
    accountManager.addCollateralFor(ALICE, subAccount0, address(weth), _aliceWethCollatAmount);
    vm.stopPrank();

    collats = viewFacet.getAllSubAccountCollats(ALICE, subAccount0);

    assertEq(collats.length, 2);
    assertEq(collats[0].amount, _aliceUsdcCollatAmount);
    assertEq(collats[1].amount, _aliceWethCollatAmount * 2, "updated weth");
  }

  function testCorrectness_WhenUserAddMultipleCollaterals_TotalBorrowingPowerShouldBeCorrect() external {
    uint256 _aliceWethCollatAmount = 10 ether;
    uint256 _aliceUsdcCollatAmount = normalizeEther(20 ether, usdcDecimal);

    vm.startPrank(ALICE);

    accountManager.addCollateralFor(ALICE, subAccount0, address(weth), _aliceWethCollatAmount);

    accountManager.addCollateralFor(ALICE, subAccount0, address(usdc), _aliceUsdcCollatAmount);
    vm.stopPrank();

    uint256 _aliceBorrowingPower = viewFacet.getTotalBorrowingPower(ALICE, subAccount0);
    assertEq(_aliceBorrowingPower, 27 ether);
  }

  function testRevert_WhenUserAddInvalidCollateral_ShouldRevert() external {
    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(LibMoneyMarket01.LibMoneyMarket01_InvalidAssetTier.selector));
    accountManager.addCollateralFor(ALICE, subAccount0, address(isolateToken), 1 ether);
    vm.stopPrank();
  }

  function testRevert_WhenUserAddCollateralMoreThanLimit_ShouldRevert() external {
    //max collat for weth is 100 ether
    uint256 _collateral = 100 ether;
    vm.startPrank(ALICE);

    // deposit and add ib as collat
    accountManager.depositAndAddCollateral(0, address(weth), 10 ether);

    /*
    The following block of code has the same effect as above
    accountManager.deposit(address(weth), 10 ether);
    ibWeth.approve(moneyMarketDiamond, 10 ether);
    accountManager.addCollateralFor(ALICE, 0, address(ibWeth), 10 ether);
    */

    // first time should pass
    accountManager.addCollateralFor(ALICE, 0, address(weth), _collateral);

    // the second should revert as it will exceed the limit
    vm.expectRevert(abi.encodeWithSelector(LibMoneyMarket01.LibMoneyMarket01_ExceedCollateralLimit.selector));
    accountManager.addCollateralFor(ALICE, 0, address(weth), _collateral);

    vm.stopPrank();
  }

  // Add Collat with ibToken
  function testCorrectness_WhenAddCollateralViaIbToken_ibTokenShouldTransferFromUserToMM() external {
    IMiniFL _miniFL = IMiniFL(address(miniFL));
    uint256 _poolId = viewFacet.getMiniFLPoolIdOfToken(address(ibWeth));

    // LEND to get ibToken
    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, 10 ether);
    accountManager.deposit(address(weth), 10 ether);
    vm.stopPrank();

    uint256 _amountOfibTokenBefore = ibWeth.balanceOf(address(moneyMarketDiamond));

    vm.warp(block.timestamp + 100);

    // Add collat by ibToken
    vm.startPrank(ALICE);
    ibWeth.approve(moneyMarketDiamond, 10 ether);
    accountManager.addCollateralFor(ALICE, subAccount0, address(ibWeth), 10 ether);
    vm.stopPrank();

    assertEq(weth.balanceOf(ALICE), 990 ether);
    assertEq(ibWeth.balanceOf(ALICE), 0 ether);

    // check account ib token collat
    // when add collat with ibToken, ibToken should get staked to MiniFL
    assertEq(viewFacet.getCollatAmountOf(ALICE, subAccount0, address(ibWeth)), 10 ether);
    assertEq(_miniFL.getUserTotalAmountOf(_poolId, ALICE), 10 ether);

    assertEq(ibWeth.balanceOf(ALICE), 0 ether);
    assertEq(ibWeth.balanceOf(address(miniFL)), 10 ether);
    assertEq(ibWeth.balanceOf(address(moneyMarketDiamond)), _amountOfibTokenBefore);
  }
}
