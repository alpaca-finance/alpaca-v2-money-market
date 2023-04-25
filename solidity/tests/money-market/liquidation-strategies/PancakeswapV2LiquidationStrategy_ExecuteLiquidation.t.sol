// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest, console, MockERC20 } from "../MoneyMarket_BaseTest.t.sol";
import { PancakeswapV2LiquidationStrategy } from "../../../contracts/money-market/PancakeswapV2LiquidationStrategy.sol";

// mocks
import { MockRouter } from "../../mocks/MockRouter.sol";
import { MockLPToken } from "../../mocks/MockLPToken.sol";

contract PancakeswapV2LiquidationStrategy_ExecuteLiquidationTest is MoneyMarket_BaseTest {
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
    _setPathsInputs[0] = PancakeswapV2LiquidationStrategy.SetPathParams({ path: _paths });

    liquidationStrat.setPaths(_setPathsInputs);
  }

  function testCorrectness_LiquidationStrat_WhenExecuteLiquidation_ShouldWork() external {
    address _collatToken = address(weth);
    address _debtToken = address(usdc);

    weth.mint(address(liquidationStrat), normalizeEther(1 ether, wethDecimal));
    usdc.mint(address(router), normalizeEther(1 ether, usdcDecimal));

    vm.prank(address(moneyMarketDiamond));
    liquidationStrat.executeLiquidation(
      _collatToken,
      _debtToken,
      normalizeEther(1 ether, wethDecimal),
      normalizeEther(1 ether, usdcDecimal),
      0
    );

    // nothing left in strat
    assertEq(weth.balanceOf(address(liquidationStrat)), 0, "weth balance of strat");
    assertEq(usdc.balanceOf(address(liquidationStrat)), 0, "usdc balance of strat");

    assertEq(
      usdc.balanceOf(address(moneyMarketDiamond)),
      normalizeEther(1 ether, usdcDecimal),
      "usdc balance of money market"
    );
    assertEq(usdc.balanceOf(address(router)), 0, "usdc balance of router");
  }

  function testCorrectness_WhenInjectCollatToStrat_ExecuteLiquidation_ShouldTransferCollatAmountBackCorrectly()
    external
  {
    address _collatToken = address(weth);
    address _debtToken = address(usdc);

    uint256 _collatAmount = normalizeEther(1 ether, wethDecimal);
    uint256 _repayAmount = normalizeEther(1 ether, usdcDecimal);

    uint256 _injectAmount = normalizeEther(1 ether, wethDecimal);
    weth.mint(address(liquidationStrat), _collatAmount + _injectAmount);
    usdc.mint(address(router), normalizeEther(1 ether, usdcDecimal));

    vm.prank(address(moneyMarketDiamond));
    liquidationStrat.executeLiquidation(_collatToken, _debtToken, _collatAmount, _repayAmount, 0);

    // injected collat left in strat
    assertEq(weth.balanceOf(address(liquidationStrat)), _injectAmount, "weth balance of strat");
    assertEq(usdc.balanceOf(address(liquidationStrat)), 0, "usdc balance of strat");

    assertEq(
      usdc.balanceOf(address(moneyMarketDiamond)),
      normalizeEther(1 ether, usdcDecimal),
      "usdc balance of money market"
    );
    assertEq(usdc.balanceOf(address(router)), 0, "usdc balance of router");
  }

  function testRevert_WhenNotOkCallersCallExecuteLiquidation_ShouldRevert() external {
    address _collatToken = address(weth);
    address _debtToken = address(usdc);

    vm.expectRevert(
      abi.encodeWithSelector(PancakeswapV2LiquidationStrategy.PancakeswapV2LiquidationStrategy_Unauthorized.selector)
    );
    liquidationStrat.executeLiquidation(
      _collatToken,
      _debtToken,
      normalizeEther(1 ether, wethDecimal),
      normalizeEther(1 ether, usdcDecimal),
      0
    );
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
    liquidationStrat.executeLiquidation(
      _collatToken,
      _debtToken,
      normalizeEther(1 ether, usdcDecimal),
      normalizeEther(1 ether, wethDecimal),
      0
    );
  }

  // TODO: multi-hop integration test with real router

  function testCorrect_WhenCallerWithdraw_ShouldWork() external {
    // mint erc20 to strat
    MockERC20 _token = new MockERC20("token0", "TK0", 18);
    uint256 _tokenDecimal = _token.decimals();

    uint256 _withdrawAmount = normalizeEther(10, _tokenDecimal);
    _token.mint(address(liquidationStrat), _withdrawAmount);

    // balance before
    uint256 _stratBalanceBefore = _token.balanceOf(address(liquidationStrat));
    uint256 _aliceBalanceBefore = _token.balanceOf(address(ALICE));

    // use caller (ALICE) to withdraw
    liquidationStrat.withdraw(ALICE, address(_token), _withdrawAmount);

    // balance after
    uint256 _stratBalanceAfter = _token.balanceOf(address(liquidationStrat));
    uint256 _aliceBalanceAfter = _token.balanceOf(address(ALICE));

    // assert
    // strat: after = before - withdraw
    assertEq(_stratBalanceAfter, _stratBalanceBefore - _withdrawAmount);
    // ALICE: after = before + withdraw
    assertEq(_aliceBalanceAfter, _aliceBalanceBefore + _withdrawAmount);
  }

  function testRevert_WhenNonCallerWithdraw_ShouldRevert() external {
    // mint erc20 to strat
    MockERC20 _token = new MockERC20("token0", "TK0", 18);
    uint256 _tokenDecimal = _token.decimals();

    uint256 _withdrawAmount = normalizeEther(10, _tokenDecimal);
    _token.mint(address(liquidationStrat), _withdrawAmount);

    vm.startPrank(BOB);
    vm.expectRevert("Ownable: caller is not the owner");
    liquidationStrat.withdraw(BOB, address(_token), _withdrawAmount);
  }
}
