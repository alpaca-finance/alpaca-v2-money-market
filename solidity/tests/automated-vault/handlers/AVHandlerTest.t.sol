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
    weth.mint(address(avHandler), 10 ether);
    usdc.mint(address(avHandler), 10 ether);

    avHandler.onDeposit(address(weth), address(usdc), 10 ether, 10 ether, 0);

    // mock router is amount0 + amount1 / 2 = (10 + 10) / 2 = 10 ether;
    assertEq(wethUsdcLPToken.balanceOf(address(avHandler)), 10 ether);
    // total lp balance should same with balance of LPToken
    assertEq(avHandler.totalLpBalance(), 10 ether);
  }

  function testRevert_WhenDepositAndGetTooLessLiquidity_ShouldRevert() external {
    weth.mint(address(avHandler), 10 ether);
    usdc.mint(address(avHandler), 10 ether);

    // mock router is amount0 + amount1 / 2 = (10 + 10) / 2 = 10 ether;
    vm.expectRevert(abi.encodeWithSelector(IAVPancakeSwapHandler.AVPancakeSwapHandler_TooLittleReceived.selector));
    avHandler.onDeposit(address(weth), address(usdc), 10 ether, 10 ether, 1000 ether);

    // check no liquidity come to handler
    assertEq(wethUsdcLPToken.balanceOf(address(avHandler)), 0 ether);
  }
}
