// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, console } from "../MoneyMarket_BaseTest.t.sol";
import { PancakeswapV2LiquidationStrategy } from "../../../contracts/money-market/PancakeswapV2LiquidationStrategy.sol";
import { MockRouter } from "../../mocks/MockRouter.sol";
import { MockLPToken } from "../../mocks/MockLPToken.sol";

contract PancakeswapV2LiquidationStrategy_Test is MoneyMarket_BaseTest {
  MockLPToken internal wethUsdcLPToken;
  MockRouter internal router;
  PancakeswapV2LiquidationStrategy internal liquidationStrat;

  function setUp() public override {
    super.setUp();

    wethUsdcLPToken = new MockLPToken("MOCK LP", "MOCK LP", 18, address(weth), address(usdc));
    router = new MockRouter(address(wethUsdcLPToken));
    liquidationStrat = new PancakeswapV2LiquidationStrategy(address(router));
  }

  function testCorrectness_LiquidationStrat_WhenExecuteLiquidation_ShouldWork() external {
    address _collatToken = address(weth);
    address _debtToken = address(usdc);

    weth.mint(address(liquidationStrat), 1 ether);
    usdc.mint(address(router), 1 ether);

    address[] memory _path = new address[](2);
    _path[0] = _collatToken;
    _path[1] = _debtToken;

    liquidationStrat.executeLiquidation(
      _collatToken,
      _debtToken,
      1 ether,
      address(moneyMarketDiamond),
      abi.encode(_path)
    );

    // nothing left in strat
    assertEq(weth.balanceOf(address(liquidationStrat)), 0);
    assertEq(usdc.balanceOf(address(liquidationStrat)), 0);

    assertEq(usdc.balanceOf(address(moneyMarketDiamond)), 1 ether);
    assertEq(usdc.balanceOf(address(router)), 0);
  }
}
