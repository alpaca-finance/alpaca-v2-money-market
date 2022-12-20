// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { AV_BaseTest } from "../AV_BaseTest.t.sol";

// interfaces
import { IAVPancakeSwapHandler } from "../../../contracts/automated-vault/interfaces/IAVPancakeSwapHandler.sol";

contract AVPancakeSwapHandlerTest is AV_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenDeposit_ShouldGetLiquidityCorreclty() external {
    weth.mint(address(handler), 10 ether);
    usdc.mint(address(handler), 10 ether);

    handler.onDeposit(address(weth), address(usdc), 10 ether, 10 ether, 0);

    // mock router is amount0 + amount1 / 2 = (10 + 10) / 2 = 10 ether;
    assertEq(wethUsdcLPToken.balanceOf(address(handler)), 10 ether);
    // total lp balance should same with balance of LPToken
    assertEq(handler.totalLpBalance(), 10 ether);
  }

  function testRevert_WhenDepositAndGetTooLessLiquidity_ShouldRevert() external {
    weth.mint(address(handler), 10 ether);
    usdc.mint(address(handler), 10 ether);

    // mock router is amount0 + amount1 / 2 = (10 + 10) / 2 = 10 ether;
    vm.expectRevert(abi.encodeWithSelector(IAVPancakeSwapHandler.AVPancakeSwapHandler_TooLittleReceived.selector));
    handler.onDeposit(address(weth), address(usdc), 10 ether, 10 ether, 1000 ether);

    // check no liquidity come to handler
    assertEq(wethUsdcLPToken.balanceOf(address(handler)), 0 ether);
  }

  function testCorrectness_WhenWithdraw_CallerShouldGetFundsCorrectly() external {
    weth.mint(address(handler), 10 ether);
    usdc.mint(address(handler), 10 ether);

    handler.onDeposit(address(weth), address(usdc), 10 ether, 10 ether, 0);

    // mock router is amount0 + amount1 / 2 = (10 + 10) / 2 = 10 ether;
    assertEq(wethUsdcLPToken.balanceOf(address(handler)), 10 ether);
    // total lp balance should same with balance of LPToken
    assertEq(handler.totalLpBalance(), 10 ether);

    mockRouter.setRemoveLiquidityAmountsOut(5 ether, 5 ether);

    uint256 avDiamondUsdcBefore = usdc.balanceOf(avDiamond);
    uint256 avDiamondWethBefore = weth.balanceOf(avDiamond);

    vm.prank(avDiamond);
    (uint256 _token0Out, uint256 _token1Out) = handler.onWithdraw(5 ether);
    // note: the amounts out is from mock
    assertEq(_token0Out, 5 ether);
    assertEq(_token1Out, 5 ether);
    assertEq(wethUsdcLPToken.balanceOf(address(handler)), 5 ether);
    assertEq(handler.totalLpBalance(), 5 ether);

    // caller should got funds
    assertEq(weth.balanceOf(avDiamond) - avDiamondUsdcBefore, 5 ether);
    assertEq(usdc.balanceOf(avDiamond) - avDiamondWethBefore, 5 ether);
  }

  function testCorrectness_WhenWithdraw_SomeoneTransferTokenDirectly_CallerShouldGetFundsCorrectly() external {
    weth.mint(address(handler), 10 ether);
    usdc.mint(address(handler), 10 ether);

    handler.onDeposit(address(weth), address(usdc), 10 ether, 10 ether, 0);

    // mock router is amount0 + amount1 / 2 = (10 + 10) / 2 = 10 ether;
    assertEq(wethUsdcLPToken.balanceOf(address(handler)), 10 ether);
    // total lp balance should same with balance of LPToken
    assertEq(handler.totalLpBalance(), 10 ether);

    mockRouter.setRemoveLiquidityAmountsOut(5 ether, 5 ether);

    vm.startPrank(BOB);
    weth.transfer(address(handler), 1 ether);
    usdc.transfer(address(handler), 2 ether);
    vm.stopPrank();

    (uint256 _token0Out, uint256 _token1Out) = handler.onWithdraw(5 ether);
    // note: the amounts out is from mock
    assertEq(_token0Out, 5 ether);
    assertEq(_token1Out, 5 ether);
    assertEq(wethUsdcLPToken.balanceOf(address(handler)), 5 ether);
    assertEq(handler.totalLpBalance(), 5 ether);

    // caller should got funds
    assertEq(weth.balanceOf(address(this)), 5 ether);
    assertEq(usdc.balanceOf(address(this)), 5 ether);
  }

  function testRevert_WhenAliceTryCallHandler_ShouldRevert() external {
    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(IAVPancakeSwapHandler.AVPancakeSwapHandler_Unauthorized.selector, ALICE));
    handler.onDeposit(address(weth), address(usdc), 10 ether, 10 ether, 0);

    vm.expectRevert(abi.encodeWithSelector(IAVPancakeSwapHandler.AVPancakeSwapHandler_Unauthorized.selector, ALICE));
    handler.onWithdraw(5 ether);
    vm.stopPrank();
  }
}
