// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest } from "../MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { ILendFacet } from "../../../contracts/money-market/interfaces/ILendFacet.sol";
import { IERC20 } from "../../../contracts/money-market/interfaces/IERC20.sol";
import { FixedInterestRateModel, IInterestRateModel } from "../../../contracts/money-market/interest-models/FixedInterestRateModel.sol";

contract MoneyMarket_Lend_DepositTest is MoneyMarket_BaseTest {
  uint256 internal _aliceWethStartingBalance;

  function setUp() public override {
    super.setUp();
    _aliceWethStartingBalance = weth.balanceOf(ALICE);
  }

  function testCorrectness_WhenUserDeposit_TokenShouldSafeTransferFromUserToMM() external {
    uint256 _depositAmount = 10 ether;
    vm.startPrank(ALICE);
    accountManager.deposit(address(weth), _depositAmount);
    vm.stopPrank();

    assertEq(weth.balanceOf(ALICE), _aliceWethStartingBalance - _depositAmount);
    assertEq(weth.balanceOf(moneyMarketDiamond), _depositAmount);

    assertEq(ibWeth.balanceOf(ALICE), _depositAmount);
  }

  function testCorrectness_WhenMultipleDeposit_ShouldMintShareCorrectly() external {
    uint256 _depositAmount1 = 10 ether;
    uint256 _depositAmount2 = 20 ether;
    uint256 _expectedTotalShare = 0;

    vm.startPrank(ALICE);
    accountManager.deposit(address(weth), _depositAmount1);
    vm.stopPrank();

    // frist deposit mintShare = depositAmount
    _expectedTotalShare += _depositAmount1;
    assertEq(ibWeth.balanceOf(ALICE), _depositAmount1);

    weth.mint(BOB, _depositAmount2);
    vm.startPrank(BOB);
    accountManager.deposit(address(weth), _depositAmount2);
    vm.stopPrank();

    // mintShare = 20 * 10 / 10 = 20
    uint256 _expectedBoBShare = 20 ether;
    _expectedTotalShare += _expectedBoBShare;
    assertEq(ibWeth.balanceOf(BOB), 20 ether);
    assertEq(ibWeth.totalSupply(), _expectedTotalShare);
  }

  function testRevert_WhenUserDepositInvalidToken_ShouldRevert() external {
    address _randomToken = address(10);
    vm.startPrank(address(accountManager));
    vm.expectRevert(abi.encodeWithSelector(ILendFacet.LendFacet_InvalidToken.selector, _randomToken));
    lendFacet.deposit(ALICE, _randomToken, 10 ether);
    vm.stopPrank();
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
    accountManager.deposit(address(weth), 10 ether);
    vm.stopPrank();

    assertEq(ibWeth.balanceOf(ALICE), 10 ether);

    vm.startPrank(BOB);
    accountManager.addCollateralFor(BOB, subAccount0, address(usdc), normalizeEther(20 ether, usdcDecimal));
    accountManager.borrow(subAccount0, address(weth), 5 ether);
    vm.stopPrank();

    // advance time for interest
    vm.warp(block.timestamp + 10 seconds);

    assertEq(viewFacet.getGlobalPendingInterest(address(weth)), 0.25 ether);

    vm.startPrank(ALICE);
    accountManager.deposit(address(weth), 5 ether);
    vm.stopPrank();

    assertEq(ibWeth.balanceOf(ALICE), 14.878048780487804878 ether);
  }

  function testCorrectness_WhenUserDepositETH_TokenShouldSafeTransferFromUserToMM() external {
    vm.prank(ALICE);
    accountManager.depositETH{ value: 10 ether }();

    assertEq(wNativeToken.balanceOf(ALICE), 0 ether);
    assertEq(ALICE.balance, 990 ether);
    assertEq(wNativeToken.balanceOf(moneyMarketDiamond), 10 ether);

    assertEq(ibWNative.balanceOf(ALICE), 10 ether);
  }

  function testRevert_UserDepositWhenMMOnEmergencyPaused_ShouldRevert() external {
    adminFacet.setEmergencyPaused(true);

    vm.expectRevert(abi.encodeWithSelector(LibMoneyMarket01.LibMoneyMarket01_EmergencyPaused.selector));
    vm.prank(address(accountManager));
    lendFacet.deposit(ALICE, address(weth), 10 ether);
  }

  function testRevert_UserDepositResultInTinyShare_ShouldRevert() external {
    vm.startPrank(address(accountManager));
    vm.expectRevert(abi.encodeWithSelector(ILendFacet.LendFacet_NoTinyShares.selector));
    lendFacet.deposit(ALICE, address(weth), 0.01 ether);
  }
}
