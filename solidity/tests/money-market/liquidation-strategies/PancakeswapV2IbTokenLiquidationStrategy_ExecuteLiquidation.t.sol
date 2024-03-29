// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest, console } from "../MoneyMarket_BaseTest.t.sol";
import { PancakeswapV2IbTokenLiquidationStrategy } from "../../../contracts/money-market/PancakeswapV2IbTokenLiquidationStrategy.sol";

// mocks
import { MockRouter } from "../../mocks/MockRouter.sol";
import { MockLPToken } from "../../mocks/MockLPToken.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";
import { MockMoneyMarket } from "../../mocks/MockMoneyMarket.sol";
import { InterestBearingToken } from "../../../contracts/money-market/InterestBearingToken.sol";

contract PancakeswapV2IbTokenLiquidationStrategy_ExecuteLiquidationTest is MoneyMarket_BaseTest {
  MockLPToken internal wethUsdcLPToken;
  MockRouter internal router;
  PancakeswapV2IbTokenLiquidationStrategy internal liquidationStrat;
  MockMoneyMarket internal moneyMarket;

  uint256 _routerUSDCBalance;
  uint256 _aliceUSDCBalance;
  uint256 _aliceWETHBalance;
  uint256 _aliceIbTokenBalance;

  function setUp() public override {
    super.setUp();

    _aliceUSDCBalance = usdc.balanceOf(ALICE);
    _aliceWETHBalance = weth.balanceOf(ALICE);

    wethUsdcLPToken = new MockLPToken("MOCK LP", "MOCK LP", 18, address(weth), address(usdc));
    router = new MockRouter(address(wethUsdcLPToken));

    moneyMarket = new MockMoneyMarket();
    moneyMarket.setIbToken(address(ibWeth), address(weth));

    liquidationStrat = new PancakeswapV2IbTokenLiquidationStrategy(address(router), address(moneyMarket));

    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;

    liquidationStrat.setCallersOk(_callers, true);

    address[] memory _paths = new address[](2);
    _paths[0] = address(weth);
    _paths[1] = address(usdc);

    PancakeswapV2IbTokenLiquidationStrategy.SetPathParams[]
      memory _setPathsInputs = new PancakeswapV2IbTokenLiquidationStrategy.SetPathParams[](1);
    _setPathsInputs[0] = PancakeswapV2IbTokenLiquidationStrategy.SetPathParams({ path: _paths });

    liquidationStrat.setPaths(_setPathsInputs);

    vm.startPrank(address(moneyMarketDiamond));
    ibWeth.onDeposit(ALICE, 0, 100 ether);
    ibWeth.transferOwnership(address(moneyMarket));
    vm.stopPrank();
    _aliceIbTokenBalance = 100 ether;

    weth.mint(address(moneyMarket), normalizeEther(100 ether, wethDecimal)); // mint to mm to trafer to strat
    // moneyMarket.setWithdrawalAmount(1 ether);

    usdc.mint(address(router), normalizeEther(100 ether, usdcDecimal)); // prepare for swap
    _routerUSDCBalance = normalizeEther(100 ether, usdcDecimal);
  }

  function testRevert_WhenExecuteLiquidation_PathConfigNotFound() external {
    vm.prank(address(ALICE));
    vm.expectRevert(
      abi.encodeWithSelector(
        PancakeswapV2IbTokenLiquidationStrategy.PancakeswapV2IbTokenLiquidationStrategy_PathConfigNotFound.selector,
        [address(weth), address(btc)]
      )
    );
    liquidationStrat.executeLiquidation(
      address(ibWeth),
      address(btc),
      normalizeEther(1 ether, ibWethDecimal),
      normalizeEther(1 ether, btcDecimal),
      0,
      ""
    );
  }

  function testCorrectness_WhenExecuteIbTokenLiquiationStrat_ShouldWork() external {
    // prepare criteria
    address _ibToken = address(ibWeth);
    address _debtToken = address(usdc);
    uint256 _ibTokenIn = normalizeEther(1 ether, ibWethDecimal);
    uint256 _repayAmount = normalizeEther(1 ether, usdcDecimal); // reflect to amountIns[0]
    uint256 _minReceive = 0;

    // _ibTokenTotalSupply = 100 ether
    // _totalTokenWithInterest = 100 ether
    // _requireAmountToWithdraw = 1 (amountIns[0]) * 100 / 100 = 1 ether
    // to withdraw, amount to withdraw = Min(_requireAmountToWithdraw, _ibTokenIn) = 1 ether

    // mock withdrawal amount
    uint256 _expectedIbTokenAmountToWithdraw = normalizeEther(1 ether, ibWethDecimal);
    uint256 _expectedWithdrawalAmount = normalizeEther(1 ether, wethDecimal);
    moneyMarket.setWithdrawalAmount(_expectedWithdrawalAmount);

    // mock convert to share function
    vm.mockCall(
      address(ibWeth),
      abi.encodeWithSelector(InterestBearingToken.convertToShares.selector, 1 ether),
      abi.encode(1 ether)
    );

    // this case will call swapTokensForExactTokens
    uint256 _expectedSwapedAmount = _repayAmount;

    vm.startPrank(ALICE);
    // transfer ib token to strat
    ibWeth.transfer(address(liquidationStrat), _ibTokenIn);
    assertEq(ibWeth.balanceOf(address(liquidationStrat)), _ibTokenIn, "ibWeth balance of liquidationStrat");
    liquidationStrat.executeLiquidation(_ibToken, _debtToken, _ibTokenIn, _repayAmount, _minReceive, "");
    vm.stopPrank();

    // nothing left in strat
    // to check underlyingToken should swap all
    assertEq(weth.balanceOf(address(liquidationStrat)), 0, "weth balance of liquidationStrat");
    // to check swapped token should be here
    assertEq(usdc.balanceOf(address(liquidationStrat)), 0, "usdc balance of liquidationStrat");

    // to check router work correctly (we can remove this assertion because this is for mock)
    assertEq(usdc.balanceOf(address(router)), _routerUSDCBalance - _expectedSwapedAmount, "usdc balance of router");
    assertEq(usdc.balanceOf(ALICE), _aliceUSDCBalance + _expectedSwapedAmount, "usdc balance of ALICE");

    // to check final ibToken should be corrected
    assertEq(
      ibWeth.balanceOf(ALICE),
      _aliceIbTokenBalance - _expectedIbTokenAmountToWithdraw,
      "ibWeth balance of ALICE"
    );
    // to check final underlying should be not affected

    assertEq(weth.balanceOf(ALICE), _aliceWETHBalance, "weth balance of ALICE");
  }

  function testCorrectness_WhenExecuteIbTokenLiquiationStratWithCollatValueThatLessThanRepayValue() external {
    // prepare criteria
    address _ibToken = address(ibWeth);
    address _debtToken = address(usdc);
    uint256 _ibTokenIn = normalizeEther(0.5 ether, ibWethDecimal);
    uint256 _repayAmount = normalizeEther(1 ether, usdcDecimal); // reflect to amountIns[0]
    uint256 _minReceive = 0;

    // _ibTokenTotalSupply = 100 ether
    // _totalTokenWithInterest = 100 ether
    // _requireAmountToWithdraw = 1 (amountIns[0]) * 100 / 100 = 1 ether
    // to withdraw, amount to withdraw = Min(_requireAmountToWithdraw, _ibTokenIn) = 0.5 ether

    // mock withdrawal amount
    uint256 _expectedIbTokenAmountToWithdraw = normalizeEther(0.5 ether, ibWethDecimal);
    uint256 _expectedWithdrawalAmount = normalizeEther(0.5 ether, wethDecimal);
    moneyMarket.setWithdrawalAmount(_expectedWithdrawalAmount);
    // mock convert to share function
    vm.mockCall(
      address(ibWeth),
      abi.encodeWithSelector(InterestBearingToken.convertToShares.selector, 1 ether),
      abi.encode(1 ether)
    );

    // this case will call swapTokensForExactTokens
    uint256 _expectedSwapedAmount = normalizeEther(0.5 ether, usdcDecimal);

    vm.startPrank(ALICE);
    // transfer ib token to strat
    ibWeth.transfer(address(liquidationStrat), _ibTokenIn);
    liquidationStrat.executeLiquidation(_ibToken, _debtToken, _ibTokenIn, _repayAmount, _minReceive, "");
    vm.stopPrank();

    // nothing left in strat
    // to check underlyingToken should swap all
    assertEq(weth.balanceOf(address(liquidationStrat)), 0, "weth balance of liquidationStrat");
    // to check swapped token should be here
    assertEq(usdc.balanceOf(address(liquidationStrat)), 0, "usdc balance of liquidationStrat");

    // to check router work correctly (we can remove this assertion because this is for mock)
    assertEq(usdc.balanceOf(address(router)), _routerUSDCBalance - _expectedSwapedAmount, "usdc balance of router");
    assertEq(usdc.balanceOf(ALICE), _aliceUSDCBalance + _expectedSwapedAmount, "usdc balance of ALICE");

    // to check final ibToken should be corrected
    assertEq(
      ibWeth.balanceOf(ALICE),
      _aliceIbTokenBalance - _expectedIbTokenAmountToWithdraw,
      "ibWeth balance of ALICE"
    );
    // to check final underlying should be not affected
    assertEq(weth.balanceOf(ALICE), _aliceWETHBalance, "weth balance of ALICE");
  }

  function testCorrectness_WhenExecuteIbTokenLiquiationStratWithCollatValueThatMoreThanRepayValue_ShouldTransferCollatBackToUserCorreclty()
    external
  {
    // prepare criteria
    address _ibToken = address(ibWeth);
    address _debtToken = address(usdc);
    uint256 _ibTokenIn = normalizeEther(1 ether, ibWethDecimal);
    uint256 _repayAmount = normalizeEther(0.5 ether, usdcDecimal); // reflect to amountIns[0]
    uint256 _minReceive = 0 ether;

    // _ibTokenTotalSupply = 100 ether
    // _totalTokenWithInterest = 100 ether
    // _requireAmountToWithdraw = 0.5 (amountIns[0]) * 100 / 100 = 0.5 ether
    // to withdraw, amount to withdraw = Min(_requireAmountToWithdraw, _ibTokenIn) = 0.5 ether

    // mock withdrawal amount
    uint256 _expectedIbTokenAmountToWithdraw = 0.5 ether;
    uint256 _expectedWithdrawalAmount = 0.5 ether;
    // mock convert to share function
    moneyMarket.setWithdrawalAmount(_expectedWithdrawalAmount);
    vm.mockCall(
      address(ibWeth),
      abi.encodeWithSelector(InterestBearingToken.convertToShares.selector, 0.5 ether),
      abi.encode(0.5 ether)
    );

    // this case will call swapTokensForExactTokens
    uint256 _expectedSwapedAmount = normalizeEther(0.5 ether, usdcDecimal);

    vm.startPrank(ALICE);
    // transfer ib token to strat
    ibWeth.transfer(address(liquidationStrat), _ibTokenIn);
    liquidationStrat.executeLiquidation(_ibToken, _debtToken, _ibTokenIn, _repayAmount, _minReceive, "");
    vm.stopPrank();

    // nothing left in strat
    // to check underlyingToken should swap all
    assertEq(weth.balanceOf(address(liquidationStrat)), 0, "weth balance of liquidationStrat");
    // to check swapped token should be here
    assertEq(usdc.balanceOf(address(liquidationStrat)), 0, "usdc balance of liquidationStrat");

    // to check router work correctly (we can remove this assertion because this is for mock)
    assertEq(usdc.balanceOf(address(router)), _routerUSDCBalance - _expectedSwapedAmount, "usdc balance of router");
    assertEq(usdc.balanceOf(ALICE), _aliceUSDCBalance + _expectedSwapedAmount, "usdc balance of ALICE");

    // to check final ibToken should be corrected
    assertEq(
      ibWeth.balanceOf(ALICE),
      _aliceIbTokenBalance - _expectedIbTokenAmountToWithdraw,
      "ibWeth balance of ALICE"
    );
    // to check final underlying should be not affected
    assertEq(weth.balanceOf(ALICE), _aliceWETHBalance, "ibWeth balance of ALICE");
  }

  function testRevert_WhenExecuteIbTokenLiquiationStratAndUnderlyingTokenAndRepayTokenAreSame() external {
    // prepare criteria
    address _ibToken = address(ibWeth);
    address _debtToken = address(weth);
    uint256 _ibTokenIn = normalizeEther(1 ether, ibWethDecimal);
    uint256 _repayAmount = normalizeEther(1 ether, wethDecimal); // is amount to withdraw
    uint256 _minReceive = 0 ether;

    // _ibTokenTotalSupply = 100 ether
    // _totalTokenWithInterest = 100 ether
    // _requireAmountToWithdraw = repay amount = 1 ether
    // to withdraw, amount to withdraw = Min(_requireAmountToWithdraw, _ibTokenIn) = 1 ether

    vm.startPrank(ALICE);
    // transfer ib token to strat
    ibWeth.transfer(address(liquidationStrat), _ibTokenIn);
    vm.expectRevert(
      abi.encodeWithSelector(
        PancakeswapV2IbTokenLiquidationStrategy
          .PancakeswapV2IbTokenLiquidationStrategy_RepayTokenIsSameWithUnderlyingToken
          .selector
      )
    );
    liquidationStrat.executeLiquidation(_ibToken, _debtToken, _ibTokenIn, _repayAmount, _minReceive, "");
    vm.stopPrank();
  }

  function testCorrect_WhenCallerWithdraw_ShouldWork() external {
    // mint erc20 to strat (token0, token1)
    MockERC20 _token0 = new MockERC20("token0", "TK0", 18);
    MockERC20 _token1 = new MockERC20("token1", "TK1", 18);
    uint256 _token0Decimal = _token0.decimals();
    uint256 _token1Decimal = _token1.decimals();

    uint256 _withdrawToken0Amount = normalizeEther(10, _token0Decimal);
    uint256 _withdrawToken1Amount = normalizeEther(10, _token1Decimal);
    _token0.mint(address(liquidationStrat), _withdrawToken0Amount);
    _token1.mint(address(liquidationStrat), _withdrawToken1Amount);

    // balance before
    uint256 _stratToken0BalanceBefore = _token0.balanceOf(address(liquidationStrat));
    uint256 _stratToken1BalanceBefore = _token1.balanceOf(address(liquidationStrat));
    uint256 _aliceToken0BalanceBefore = _token0.balanceOf(address(ALICE));
    uint256 _aliceToken1BalanceBefore = _token1.balanceOf(address(ALICE));

    // use owner to withdraw
    PancakeswapV2IbTokenLiquidationStrategy.WithdrawParam[]
      memory _withdrawParams = new PancakeswapV2IbTokenLiquidationStrategy.WithdrawParam[](2);
    _withdrawParams[0] = PancakeswapV2IbTokenLiquidationStrategy.WithdrawParam(
      ALICE,
      address(_token0),
      _withdrawToken0Amount
    );
    _withdrawParams[1] = PancakeswapV2IbTokenLiquidationStrategy.WithdrawParam(
      ALICE,
      address(_token1),
      _withdrawToken1Amount
    );

    liquidationStrat.withdraw(_withdrawParams);

    // balance after
    uint256 _stratToken0BalanceAfter = _token0.balanceOf(address(liquidationStrat));
    uint256 _stratToken1BalanceAfter = _token1.balanceOf(address(liquidationStrat));
    uint256 _aliceToken0BalanceAfter = _token0.balanceOf(address(ALICE));
    uint256 _aliceToken1BalanceAfter = _token1.balanceOf(address(ALICE));

    // assert
    // strat: after = before - withdraw
    assertEq(_stratToken0BalanceAfter, _stratToken0BalanceBefore - _withdrawToken0Amount);
    assertEq(_stratToken1BalanceAfter, _stratToken1BalanceBefore - _withdrawToken1Amount);
    // ALICE: after = before + withdraw
    assertEq(_aliceToken0BalanceAfter, _aliceToken0BalanceBefore + _withdrawToken0Amount);
    assertEq(_aliceToken1BalanceAfter, _aliceToken1BalanceBefore + _withdrawToken1Amount);
  }

  function testRevert_WhenNonCallerWithdraw_ShouldRevert() external {
    // mint erc20 to strat
    MockERC20 _token = new MockERC20("token0", "TK0", 18);
    uint256 _tokenDecimal = _token.decimals();

    uint256 _withdrawAmount = normalizeEther(10, _tokenDecimal);
    _token.mint(address(liquidationStrat), _withdrawAmount);

    PancakeswapV2IbTokenLiquidationStrategy.WithdrawParam[]
      memory _withdrawParams = new PancakeswapV2IbTokenLiquidationStrategy.WithdrawParam[](1);
    _withdrawParams[0] = PancakeswapV2IbTokenLiquidationStrategy.WithdrawParam(ALICE, address(_token), _withdrawAmount);

    // prank to BOB and call withdraw
    vm.startPrank(BOB);
    vm.expectRevert("Ownable: caller is not the owner");
    liquidationStrat.withdraw(_withdrawParams);
  }
}
