// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, console } from "../MoneyMarket_BaseTest.t.sol";
import { PancakeswapV2LiquidationStrategy } from "../../../contracts/money-market/PancakeswapV2LiquidationStrategy.sol";

// mocks
import { MockRouter } from "../../mocks/MockRouter.sol";
import { MockLPToken } from "../../mocks/MockLPToken.sol";

contract PancakeswapV2LiquidationStrategy_SetConfigsTest is MoneyMarket_BaseTest {
  MockLPToken internal wethUsdcLPToken;
  MockRouter internal router;
  PancakeswapV2LiquidationStrategy internal liquidationStrat;

  function setUp() public override {
    super.setUp();

    wethUsdcLPToken = new MockLPToken("MOCK LP", "MOCK LP", 18, address(weth), address(usdc));
    router = new MockRouter(address(wethUsdcLPToken));
    liquidationStrat = new PancakeswapV2LiquidationStrategy(address(router));
  }

  function testCorrectness_WhenOwnerSetCallersOk_ShouldWork() external {
    address[] memory _callers = new address[](1);
    _callers[0] = EVE;

    liquidationStrat.setCallersOk(_callers, true);

    assertTrue(liquidationStrat.callersOk(EVE));
  }

  function testRevert_WhenNonOwnerSetCallersOk_ShouldRevert() external {
    address[] memory _callers = new address[](1);
    _callers[0] = EVE;

    vm.prank(EVE);
    vm.expectRevert("Ownable: caller is not the owner");
    liquidationStrat.setCallersOk(_callers, true);
  }

  function testCorrentness_WhenOwnerSetPathSingleHop_ShouldWork() external {
    address _token0 = address(usdc);
    address _token1 = address(weth);

    address[] memory _paths = new address[](2);
    _paths[0] = _token0;
    _paths[1] = _token1;

    PancakeswapV2LiquidationStrategy.SetPathParams[]
      memory _setPathsInputs = new PancakeswapV2LiquidationStrategy.SetPathParams[](1);
    _setPathsInputs[0] = PancakeswapV2LiquidationStrategy.SetPathParams({ path: _paths });

    liquidationStrat.setPaths(_setPathsInputs);

    assertEq(liquidationStrat.paths(_token0, _token1, 0), _token0);
    assertEq(liquidationStrat.paths(_token0, _token1, 1), _token1);
  }

  function testRevert_WhenNonOwnerSetPaths() external {
    address _token0 = address(usdc);
    address _token1 = address(weth);

    address[] memory _paths = new address[](2);
    _paths[0] = _token0;
    _paths[1] = _token1;

    PancakeswapV2LiquidationStrategy.SetPathParams[]
      memory _setPathsInputs = new PancakeswapV2LiquidationStrategy.SetPathParams[](1);
    _setPathsInputs[0] = PancakeswapV2LiquidationStrategy.SetPathParams({ path: _paths });

    vm.prank(ALICE);
    vm.expectRevert("Ownable: caller is not the owner");
    liquidationStrat.setPaths(_setPathsInputs);
  }

  /// @dev must disable sanity check in strat for this test to work
  /// since mockRouter only have single hop and will fail sanity check
  /// but it should work with real router with valid path
  // function testCorrectness_WhenOwnerSetPathMultiHop_ShouldWork() external {
  //   address _token0 = address(usdc);
  //   address _token1 = address(weth);
  //   address _token2 = address(btc);

  // address[] memory _paths = new address[](3);
  // _paths[0] = _token0;
  // _paths[1] = _token1;
  // _paths[2] = _token2;

  // PancakeswapV2LiquidationStrategy.SetPathParams[]
  //   memory _setPathsInputs = new PancakeswapV2LiquidationStrategy.SetPathParams[](1);
  // _setPathsInputs[0] = PancakeswapV2LiquidationStrategy.SetPathParams({ path: _paths });

  // liquidationStrat.setPaths(_setPathsInputs);

  //   liquidationStrat.setPaths(_paths);

  //   assertEq(liquidationStrat.paths(_token0, _token2, 0), _token0);
  //   assertEq(liquidationStrat.paths(_token0, _token2, 1), _token1);
  //   assertEq(liquidationStrat.paths(_token0, _token2, 2), _token2);
  // }

  // TODO: fail case when set path that doesn't exist (have 0 liquidity)
  // can't test this case with mock
}
