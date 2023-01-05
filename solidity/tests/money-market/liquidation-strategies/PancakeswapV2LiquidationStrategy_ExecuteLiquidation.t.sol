// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, console } from "../MoneyMarket_BaseTest.t.sol";
import { PancakeswapV2LiquidationStrategy } from "../../../contracts/money-market/PancakeswapV2LiquidationStrategy.sol";

// mocks
import { MockRouter } from "../../mocks/MockRouter.sol";
import { MockLPToken } from "../../mocks/MockLPToken.sol";

contract PancakeswapV2LiquidationStrategy_ExecuteLiquidation is MoneyMarket_BaseTest {
  MockLPToken internal wethUsdcLPToken;
  MockRouter internal router;
  PancakeswapV2LiquidationStrategy internal liquidationStrat;

  function setUp() public override {
    super.setUp();

    wethUsdcLPToken = new MockLPToken("MOCK LP", "MOCK LP", 18, address(weth), address(usdc));
    router = new MockRouter(address(wethUsdcLPToken));
    liquidationStrat = new PancakeswapV2LiquidationStrategy(address(router));

    address[] memory _callers = new address[](1);
    _callers[0] = address(moneyMarketDiamond);

    liquidationStrat.setCallersOk(_callers, true);

    address[] memory _paths = new address[](2);
    _paths[0] = address(weth);
    _paths[1] = address(usdc);

    PancakeswapV2LiquidationStrategy.SetPathParams[]
      memory _setPathsInputs = new PancakeswapV2LiquidationStrategy.SetPathParams[](1);
    _setPathsInputs[0] = PancakeswapV2LiquidationStrategy.SetPathParams({
      tokenIn: address(weth),
      tokenOut: address(usdc),
      path: _paths
    });

    liquidationStrat.setPaths(_setPathsInputs);
  }

  function testCorrectness_LiquidationStrat_WhenExecuteLiquidation_ShouldWork() external {
    address _collatToken = address(weth);
    address _debtToken = address(usdc);

    weth.mint(address(liquidationStrat), 1 ether);
    usdc.mint(address(router), 1 ether);

    vm.prank(address(moneyMarketDiamond));
    liquidationStrat.executeLiquidation(_collatToken, _debtToken, 1 ether, 1 ether, abi.encode(0));

    // nothing left in strat
    assertEq(weth.balanceOf(address(liquidationStrat)), 0);
    assertEq(usdc.balanceOf(address(liquidationStrat)), 0);

    assertEq(usdc.balanceOf(address(moneyMarketDiamond)), 1 ether);
    assertEq(usdc.balanceOf(address(router)), 0);
  }

  function testCorrectness_WhenInjectCollatToStrat_ExecuteLiquidation_ShouldTransferCollatAmountBackCorrectly()
    external
  {
    address _collatToken = address(weth);
    address _debtToken = address(usdc);

    uint256 _collatAmount = 1 ether;
    uint256 _repayAmount = 1 ether;

    uint256 _injectAmount = 1 ether;
    weth.mint(address(liquidationStrat), _collatAmount + _injectAmount);
    usdc.mint(address(router), 1 ether);

    vm.prank(address(moneyMarketDiamond));
    liquidationStrat.executeLiquidation(_collatToken, _debtToken, _collatAmount, _repayAmount, abi.encode(0));

    // injected collat left in strat
    assertEq(weth.balanceOf(address(liquidationStrat)), _injectAmount);
    assertEq(usdc.balanceOf(address(liquidationStrat)), 0);

    assertEq(usdc.balanceOf(address(moneyMarketDiamond)), 1 ether);
    assertEq(usdc.balanceOf(address(router)), 0);
  }

  function testRevert_WhenNotOkCallersCallExecuteLiquidation_ShouldRevert() external {
    address _collatToken = address(weth);
    address _debtToken = address(usdc);

    vm.expectRevert(
      abi.encodeWithSelector(PancakeswapV2LiquidationStrategy.PancakeswapV2LiquidationStrategy_Unauthorized.selector)
    );
    liquidationStrat.executeLiquidation(_collatToken, _debtToken, 1 ether, 1 ether, abi.encode(0));
  }

  function testRevert_WhenExecuteLiquidationOnNonExistentPath() external {
    address _collatToken = address(usdc);
    address _debtToken = address(weth);

    vm.prank(address(moneyMarketDiamond));
    vm.expectRevert(
      abi.encodeWithSelector(
        PancakeswapV2LiquidationStrategy.PancakeswapV2LiquidationStrategy_PathConfigNotFound.selector,
        _collatToken,
        _debtToken
      )
    );
    liquidationStrat.executeLiquidation(_collatToken, _debtToken, 1 ether, 1 ether, abi.encode(0));
  }

  // TODO: multi-hop integration test with real router
}
