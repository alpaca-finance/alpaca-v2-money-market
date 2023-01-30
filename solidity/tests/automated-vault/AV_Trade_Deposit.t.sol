// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { AV_BaseTest, console } from "./AV_BaseTest.t.sol";

import { LibAV01 } from "../../contracts/automated-vault/libraries/LibAV01.sol";

contract AV_Trade_DepositTest is AV_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenDepositToken_ShouldWork() external {
    uint256 _usdcAmountIn = 10 ether;
    uint256 _minShareOut = 10 ether;

    uint256 _usdcBalanceBefore = usdc.balanceOf(ALICE);

    vm.prank(ALICE);
    tradeFacet.deposit(address(vaultToken), _usdcAmountIn, _minShareOut);

    // leverage level is 3
    // price of weth and usdc are 1 USD
    // to calculate borrowed statble token, depositedAmount * leverageLevel - depositedAmount
    // target value = 10 * 3 = 30, then each side has borrowed value 30 / 2 = 15
    // then borrowed stable token is 15 - 10 = 5
    // to calculate borrowed asset token, depositedAmount * leverageLevel
    // then borrowed asset token is 15
    (uint256 _stableDebtValue, uint256 _assetDebtValue) = viewFacet.getDebtValues(address(vaultToken));
    assertEq(_stableDebtValue, 5 ether);
    assertEq(_assetDebtValue, 15 ether);

    // equity change
    // before deposit
    // lpAmountPrice = 2, wethPrice = 1, usdcPrice = 1
    // lpAmount = 0, wethDebtAmount = 0, usdcDebtAmount = 0
    // equityBefore = (0 * 2) - ((0 * 1) + (0 * 1)) = 0
    // after deposit
    // lpAmount = 15, wethDebtAmount = 5, usdcDebtAmount = 15
    // equityAfter = (15 * 2) - ((5 * 1) + (15 * 1)) = 30 - 20 = 10
    // equity change = 10
    // avToken totalSupply = 0
    // given shareToMint = equityChange * totalSupply (avToken) / totalEquity
    // in this case is first mint, so shareToMint will be equityChange
    // shareToMint = 10
    assertEq(vaultToken.balanceOf(ALICE), 10 ether);
    assertEq(_usdcBalanceBefore - usdc.balanceOf(ALICE), _usdcAmountIn);

    // note: for mock router compose LP
    // check liquidty in handler, 15 + 15 / 2 = 15
    assertEq(handler.totalLpBalance(), 15 ether);

    // subsequent deposit should work
    _usdcBalanceBefore = usdc.balanceOf(BOB);

    vm.prank(BOB);
    tradeFacet.deposit(address(vaultToken), _usdcAmountIn, _minShareOut);

    // check BOB balance
    assertEq(vaultToken.balanceOf(BOB), 10 ether);
    assertEq(_usdcBalanceBefore - usdc.balanceOf(BOB), _usdcAmountIn);

    // check vault state
    // BOB deposit same amount as ALICE so everything in vault should double
    (_stableDebtValue, _assetDebtValue) = viewFacet.getDebtValues(address(vaultToken));
    assertEq(_stableDebtValue, 10 ether);
    assertEq(_assetDebtValue, 30 ether);
    assertEq(handler.totalLpBalance(), 30 ether);
  }

  function testRevert_WhenDepositTokenAndGetTinyShares_ShouldRevert() external {
    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(LibAV01.LibAV01_NoTinyShares.selector));
    tradeFacet.deposit(address(vaultToken), 0.05 ether, 0.05 ether);
    vm.stopPrank();
  }

  // TODO: enable this test and remove testRevert_WhenDepositTokenAndGetTinyShares_ShouldRevert
  // when done with withdraw and tiny share
  //   function testCorrectness_WhenTryToExploitTinysharesOnAV_ShouldDepositWithdrawCorrectlyWithoutTinyShares() external {
  //     // no tiny share exploit since we use reserves state variable internally instead of balanceOf

  //     // exploiter deposit 10 wei usdc, get 10 wei shareToken back
  //     vm.startPrank(ALICE);
  //     tradeFacet.deposit(address(vaultToken), 10, 10);

  //     assertEq(vaultToken.balanceOf(ALICE), 10);
  //     assertEq(handler.totalLpBalance(), 15);

  //     // exploiter direct transfer 1B lp
  //     wethUsdcLPToken.mint(ALICE, 1e10 ether);
  //     wethUsdcLPToken.transfer(address(handler), 1e10 ether);
  //     vm.stopPrank();

  //     assertEq(handler.totalLpBalance(), 15);

  //     // user deposit 1M usdc, get 1M shareToken back
  //     console.log("==========");
  //     usdc.mint(BOB, 1e7 ether);
  //     vm.startPrank(BOB);
  //     tradeFacet.deposit(address(vaultToken), 1e7 ether, 1e7 ether);

  //     assertEq(vaultToken.balanceOf(BOB), 1e7 ether);

  //     // user withdraw 1M ibWeth, get 1M weth back
  //     uint256 _bobUsdcBalanceBefore = usdc.balanceOf(BOB);
  //     tradeFacet.withdraw(address(vaultToken), 1e7 ether, 1e7 ether);

  //     assertEq(usdc.balanceOf(BOB) - _bobUsdcBalanceBefore, 1e7 ether);
  //     vm.stopPrank();

  //     // exploiter withdraw 10 wei share, get 10 wei usdc back
  //     uint256 _aliceUsdcBalanceBefore = usdc.balanceOf(ALICE);

  //     vm.prank(ALICE);
  //     tradeFacet.withdraw(address(vaultToken), 10, 10);

  //     assertEq(usdc.balanceOf(ALICE) - _aliceUsdcBalanceBefore, 1);
  //   }
}
