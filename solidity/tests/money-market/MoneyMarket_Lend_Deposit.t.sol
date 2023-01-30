// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { ILendFacet } from "../../contracts/money-market/facets/LendFacet.sol";
import { IERC20 } from "../../contracts/money-market/interfaces/IERC20.sol";
import { FixedInterestRateModel, IInterestRateModel } from "../../contracts/money-market/interest-models/FixedInterestRateModel.sol";

contract MoneyMarket_Lend_DepositTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenUserDeposit_TokenShouldSafeTransferFromUserToMM() external {
    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, 10 ether);
    lendFacet.deposit(address(weth), 10 ether);
    vm.stopPrank();

    assertEq(weth.balanceOf(ALICE), 990 ether);
    assertEq(weth.balanceOf(moneyMarketDiamond), 10 ether);

    assertEq(ibWeth.balanceOf(ALICE), 10 ether);
  }

  function testCorrectness_WhenMultipleDeposit_ShouldMintShareCorrectly() external {
    uint256 _depositAmount1 = 10 ether;
    uint256 _depositAmount2 = 20 ether;
    uint256 _expectedTotalShare = 0;

    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, _depositAmount1);
    lendFacet.deposit(address(weth), _depositAmount1);
    vm.stopPrank();

    // frist deposit mintShare = depositAmount
    _expectedTotalShare += _depositAmount1;
    assertEq(ibWeth.balanceOf(ALICE), _depositAmount1);

    weth.mint(BOB, _depositAmount2);
    vm.startPrank(BOB);
    weth.approve(moneyMarketDiamond, _depositAmount2);
    lendFacet.deposit(address(weth), _depositAmount2);
    vm.stopPrank();

    // mintShare = 20 * 10 / 10 = 20
    uint256 _expectedBoBShare = 20 ether;
    _expectedTotalShare += _expectedBoBShare;
    assertEq(ibWeth.balanceOf(BOB), 20 ether);
    assertEq(ibWeth.totalSupply(), _expectedTotalShare);
  }

  function testRevert_WhenUserDepositInvalidToken_ShouldRevert() external {
    address _randomToken = address(10);
    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(ILendFacet.LendFacet_InvalidToken.selector, _randomToken));
    lendFacet.deposit(_randomToken, 10 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserDepositETH_TokenShouldSafeTransferFromUserToMM() external {
    vm.prank(ALICE);
    lendFacet.depositETH{ value: 10 ether }();

    assertEq(wNativeToken.balanceOf(ALICE), 0 ether);
    assertEq(ALICE.balance, 990 ether);
    assertEq(wNativeToken.balanceOf(moneyMarketDiamond), 10 ether);

    assertEq(ibWNative.balanceOf(ALICE), 10 ether);
  }

  function testCorrectness_WhenUserDepositWithUnaccrueInterest_ShouldMintShareCorrectly() external {
    /**
     * scenario:
     *
     * 1. Alice deposit 10 weth and get 10 ibWeth
     *
     * 2. Bob add collateral and borrow 5 weth out
     *
     * 3. After 10 seconds, alice deposit another 5 weth
     *    - interest 0.1% per second, getGlobalPendingInterest = 5 * 10 * (5 * 0.001) = 0.25 weth
     *    - totalToken = 10.25, totalSupply = 10
     *    - alice should get 5 * 10 / 10.25 = 4.878048780487804878
     *    - alice's total ibWeth = 14.878048780487804878
     */

    FixedInterestRateModel model = new FixedInterestRateModel(wethDecimal);
    adminFacet.setInterestModel(address(weth), address(model));
    borrowFacet.accrueInterest(address(weth));

    vm.startPrank(ALICE);
    lendFacet.deposit(address(weth), 10 ether);
    vm.stopPrank();

    assertEq(ibWeth.balanceOf(ALICE), 10 ether);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), 20 ether);
    borrowFacet.borrow(subAccount0, address(weth), 5 ether);
    vm.stopPrank();

    // advance time for interest
    vm.warp(block.timestamp + 10 seconds);

    assertEq(viewFacet.getGlobalPendingInterest(address(weth)), 0.25 ether);

    vm.startPrank(ALICE);
    lendFacet.deposit(address(weth), 5 ether);
    vm.stopPrank();

    assertEq(ibWeth.balanceOf(ALICE), 14.878048780487804878 ether);
  }
}
