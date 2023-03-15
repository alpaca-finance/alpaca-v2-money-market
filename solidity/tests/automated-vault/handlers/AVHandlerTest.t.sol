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
    usdc.mint(address(handler), normalizeEther(10 ether, usdcDecimal));

    handler.onDeposit(address(usdc), address(weth), normalizeEther(10 ether, usdcDecimal), 10 ether, 0);

    // mock router is amount0 + amount1 / 2 = (10 + 10) / 2 = 10 ether;
    assertEq(usdcWethLPToken.balanceOf(address(handler)), 10 ether);
    // total lp balance should same with balance of LPToken
    assertEq(handler.totalLpBalance(), 10 ether);
    // total aum should be 10 * 2(lp value) = 20 ether
    assertEq(handler.getAUMinUSD(), 20 ether);
  }

  function testRevert_WhenDepositAndGetTooLessLiquidity_ShouldRevert() external {
    weth.mint(address(handler), 10 ether);
    usdc.mint(address(handler), normalizeEther(10 ether, usdcDecimal));

    // mock router is amount0 + amount1 / 2 = (10 + 10) / 2 = 10 ether;
    vm.expectRevert(abi.encodeWithSelector(IAVPancakeSwapHandler.AVPancakeSwapHandler_TooLittleReceived.selector));
    handler.onDeposit(address(usdc), address(weth), normalizeEther(10 ether, usdcDecimal), 10 ether, 10000 ether);

    // check no liquidity come to handler
    assertEq(usdcWethLPToken.balanceOf(address(handler)), 0 ether);
  }

  function testCorrectness_WhenWithdraw_CallerShouldGetFundsCorrectly() external {
    weth.mint(address(handler), 10 ether);
    usdc.mint(address(handler), normalizeEther(10 ether, usdcDecimal));

    handler.onDeposit(address(usdc), address(weth), normalizeEther(10 ether, usdcDecimal), 10 ether, 0);

    // mock router is amount0 + amount1 / 2 = (10 + 10) / 2 = 10 ether;
    assertEq(usdcWethLPToken.balanceOf(address(handler)), 10 ether);
    // total lp balance should same with balance of LPToken
    assertEq(handler.totalLpBalance(), 10 ether);
    // total aum should be 10 * 2(lp value) = 20 ether
    uint256 _tvl = handler.getAUMinUSD();
    assertEq(_tvl, 20 ether);

    mockRouter.setRemoveLiquidityAmountsOut(normalizeEther(5 ether, usdcDecimal), 5 ether);

    uint256 avDiamondUsdcBefore = usdc.balanceOf(avDiamond);
    uint256 avDiamondWethBefore = weth.balanceOf(avDiamond);

    vm.prank(avDiamond);
    // trying to remove half of the TVL
    // since there's 20 USD, trying to remove half should get 5 usdc and 5 weth
    (uint256 _token0Out, uint256 _token1Out) = handler.onWithdraw(_tvl / 2);

    // note: the amounts out is from mock
    assertEq(_token0Out, normalizeEther(5 ether, usdcDecimal));
    assertEq(_token1Out, 5 ether);
    assertEq(usdcWethLPToken.balanceOf(address(handler)), 5 ether);
    assertEq(handler.totalLpBalance(), 5 ether);

    // caller should got funds
    assertEq(weth.balanceOf(avDiamond) - avDiamondUsdcBefore, 5 ether);
    assertEq(usdc.balanceOf(avDiamond) - avDiamondWethBefore, normalizeEther(5 ether, usdcDecimal));
  }

  function testCorrectness_WhenWithdraw_SomeoneTransferTokenDirectly_CallerShouldGetFundsCorrectly() external {
    weth.mint(address(handler), 10 ether);
    usdc.mint(address(handler), normalizeEther(10 ether, usdcDecimal));

    handler.onDeposit(address(usdc), address(weth), normalizeEther(10 ether, usdcDecimal), 10 ether, 0);

    // mock router is amount0 + amount1 / 2 = (10 + 10) / 2 = 10 ether;
    assertEq(usdcWethLPToken.balanceOf(address(handler)), 10 ether);
    // total lp balance should same with balance of LPToken
    assertEq(handler.totalLpBalance(), 10 ether);
    // total aum should be 10 * 2(lp value) = 20 ether
    uint256 _tvl = handler.getAUMinUSD();
    assertEq(_tvl, 20 ether);

    mockRouter.setRemoveLiquidityAmountsOut(normalizeEther(5 ether, usdcDecimal), 5 ether);

    vm.startPrank(BOB);
    weth.transfer(address(handler), 1 ether);
    usdc.transfer(address(handler), normalizeEther(2 ether, usdcDecimal));
    vm.stopPrank();

    // trying to remove half of the TVL
    // since there's 20 USD, trying to remove half should get 5 usdc and 5 weth
    (uint256 _token0Out, uint256 _token1Out) = handler.onWithdraw(_tvl / 2);
    // note: the amounts out is from mock
    assertEq(_token0Out, normalizeEther(5 ether, usdcDecimal));
    assertEq(_token1Out, 5 ether);
    assertEq(usdcWethLPToken.balanceOf(address(handler)), 5 ether);
    assertEq(handler.totalLpBalance(), 5 ether);

    // caller should got funds
    assertEq(weth.balanceOf(address(this)), 5 ether);
    assertEq(usdc.balanceOf(address(this)), normalizeEther(5 ether, usdcDecimal));
  }

  function testRevert_WhenAliceTryCallHandler_ShouldRevert() external {
    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(IAVPancakeSwapHandler.AVPancakeSwapHandler_Unauthorized.selector, ALICE));
    handler.onDeposit(address(usdc), address(weth), normalizeEther(10 ether, usdcDecimal), 10 ether, 0);

    vm.expectRevert(abi.encodeWithSelector(IAVPancakeSwapHandler.AVPancakeSwapHandler_Unauthorized.selector, ALICE));
    handler.onWithdraw(5 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenComposeLPTokenWithToken01OrderSwapped_ShouldWork() external {
    // should work regardless of token ordering
    // token0 = weth, token1 = usdc
    weth.mint(address(handler), 10 ether);
    usdc.mint(address(handler), normalizeEther(10 ether, usdcDecimal));
    handler.onDeposit(address(weth), address(usdc), 10 ether, normalizeEther(10 ether, usdcDecimal), 0);
    assertEq(handler.totalLpBalance(), 10 ether);

    // token0 = usdc, token1 = weth
    weth.mint(address(handler), 10 ether);
    usdc.mint(address(handler), normalizeEther(10 ether, usdcDecimal));
    handler.onDeposit(address(usdc), address(weth), normalizeEther(10 ether, usdcDecimal), 10 ether, 0);
    assertEq(handler.totalLpBalance(), 20 ether);
  }
}
