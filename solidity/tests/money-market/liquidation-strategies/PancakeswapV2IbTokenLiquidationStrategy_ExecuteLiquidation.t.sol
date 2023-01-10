// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, console } from "../MoneyMarket_BaseTest.t.sol";
import { PancakeswapV2IbTokenLiquidationStrategy } from "../../../contracts/money-market/PancakeswapV2IbTokenLiquidationStrategy.sol";

// mocks
import { MockRouter } from "../../mocks/MockRouter.sol";
import { MockLPToken } from "../../mocks/MockLPToken.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";
import { MockMoneyMarket } from "../../mocks/MockMoneyMarket.sol";

contract PancakeswapV2IbTokenLiquidationStrategy_ExecuteLiquidation is MoneyMarket_BaseTest {
  MockLPToken internal wethUsdcLPToken;
  MockRouter internal router;
  PancakeswapV2IbTokenLiquidationStrategy internal liquidationStrat;
  MockMoneyMarket internal moneyMarket;

  uint256 _routerUSDCBalance;
  uint256 _aliceUSDCBalance = 1000 ether; // minting in BaseTest
  uint256 _aliceIbTokenBalance;

  function setUp() public override {
    super.setUp();

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

    vm.prank(address(moneyMarketDiamond));
    ibWeth.onDeposit(ALICE, 0, 100 ether);
    _aliceIbTokenBalance = 100 ether;

    weth.mint(address(moneyMarket), 100 ether); // mint to mm to trafer to strat
    // moneyMarket.setWithdrawalAmount(1 ether);

    usdc.mint(address(router), 100 ether); // prepare for swap
    _routerUSDCBalance = 100 ether;
  }

  function testRevert_WhenExecuteLiquidation_InvalidIbToken() external {
    vm.prank(address(ALICE));
    vm.expectRevert(
      abi.encodeWithSelector(
        PancakeswapV2IbTokenLiquidationStrategy.PancakeswapV2IbTokenLiquidationStrategy_InvalidIbToken.selector,
        [address(ibBtc)]
      )
    );
    liquidationStrat.executeLiquidation(address(ibBtc), address(usdc), 1 ether, 1 ether, abi.encode(0));
  }

  function testRevert_WhenExecuteLiquidation_PathConfigNotFound() external {
    vm.prank(address(ALICE));
    vm.expectRevert(
      abi.encodeWithSelector(
        PancakeswapV2IbTokenLiquidationStrategy.PancakeswapV2IbTokenLiquidationStrategy_PathConfigNotFound.selector,
        [address(weth), address(btc)]
      )
    );
    liquidationStrat.executeLiquidation(address(ibWeth), address(btc), 1 ether, 1 ether, abi.encode(0));
  }

  function testCorrectness_IbTokenLiquidationStrat_WhenExecuteLiquidation_ShouldWork() external {
    // prepare criteria
    address _ibToken = address(ibWeth);
    address _debtToken = address(usdc);
    uint256 _ibTokenIn = 1 ether;
    uint256 _repayAmount = 1 ether; // reflect to amountIns[0]
    uint256 _minReceive = 0 ether;

    // _ibTokenTotalSupply = 100 ether
    // _totalTokenWithInterest = 100 ether
    // _requireAmountToWithdraw = 1 (amountIns[0]) * 100 / 100 = 1 ether
    // to withdraw, amount to withdraw = Min(_requireAmountToWithdraw, _ibTokenIn) = 1 ether

    // mock withdrawal amount
    uint256 _expectedWithdrawalAmount = 1 ether;
    moneyMarket.setWithdrawalAmount(_expectedWithdrawalAmount);

    // this case will call swapTokensForExactTokens
    uint256 _expectedSwapedAmount = _repayAmount;

    vm.startPrank(ALICE);
    // transfer ib token to strat
    ibWeth.transfer(address(liquidationStrat), _ibTokenIn);
    assertEq(ibWeth.balanceOf(address(liquidationStrat)), _ibTokenIn, "ibWeth balance of liquidationStrat");
    liquidationStrat.executeLiquidation(_ibToken, _debtToken, _ibTokenIn, _repayAmount, abi.encode(_minReceive));
    vm.stopPrank();

    // nothing left in strat
    // to check ibToken should not exists on liquidation strat
    assertEq(ibWeth.balanceOf(address(liquidationStrat)), 0, "ibWeth balance of liquidationStrat");
    // to check underlyingToken should swap all
    assertEq(weth.balanceOf(address(liquidationStrat)), 0, "weth balance of liquidationStrat");
    // to check swapped token should be here
    assertEq(usdc.balanceOf(address(liquidationStrat)), 0, "usdc balance of liquidationStrat");

    // to check router work correctly (we can remove this assertion because this is for mock)
    assertEq(usdc.balanceOf(address(router)), _routerUSDCBalance - _expectedSwapedAmount, "usdc balance of router");
    assertEq(usdc.balanceOf(ALICE), _aliceUSDCBalance + _expectedSwapedAmount, "usdc balance of ALICE");

    // to check final ibToken should be corrected
    assertEq(ibWeth.balanceOf(ALICE), _aliceIbTokenBalance - _expectedWithdrawalAmount, "ibWeth balance of ALICE");
  }

  function testCorrectness_IbTokenLiquidationStrat_WhenExecuteLiquidationWithIbTokenLessThanRequireAmount_ShouldWork()
    external
  {
    // prepare criteria
    address _ibToken = address(ibWeth);
    address _debtToken = address(usdc);
    uint256 _ibTokenIn = 0.5 ether;
    uint256 _repayAmount = 1 ether; // reflect to amountIns[0]
    uint256 _minReceive = 0 ether;

    // _ibTokenTotalSupply = 100 ether
    // _totalTokenWithInterest = 100 ether
    // _requireAmountToWithdraw = 1 (amountIns[0]) * 100 / 100 = 1 ether
    // to withdraw, amount to withdraw = Min(_requireAmountToWithdraw, _ibTokenIn) = 0.5 ether

    // mock withdrawal amount
    uint256 _expectedWithdrawalAmount = 0.5 ether;
    moneyMarket.setWithdrawalAmount(_expectedWithdrawalAmount);

    // this case will call swapTokensForExactTokens
    uint256 _expectedSwapedAmount = 0.5 ether;

    vm.startPrank(ALICE);
    // transfer ib token to strat
    ibWeth.transfer(address(liquidationStrat), _ibTokenIn);
    liquidationStrat.executeLiquidation(_ibToken, _debtToken, _ibTokenIn, _repayAmount, abi.encode(_minReceive));
    vm.stopPrank();

    // nothing left in strat
    // to check ibToken should not exists on liquidation strat
    assertEq(ibWeth.balanceOf(address(liquidationStrat)), 0, "ibWeth balance of liquidationStrat");
    // to check underlyingToken should swap all
    assertEq(weth.balanceOf(address(liquidationStrat)), 0, "weth balance of liquidationStrat");
    // to check swapped token should be here
    assertEq(usdc.balanceOf(address(liquidationStrat)), 0, "usdc balance of liquidationStrat");

    // to check router work correctly (we can remove this assertion because this is for mock)
    assertEq(usdc.balanceOf(address(router)), _routerUSDCBalance - _expectedSwapedAmount, "usdc balance of router");
    assertEq(usdc.balanceOf(ALICE), _aliceUSDCBalance + _expectedSwapedAmount, "usdc balance of ALICE");

    // to check final ibToken should be corrected
    assertEq(ibWeth.balanceOf(ALICE), _aliceIbTokenBalance - _expectedWithdrawalAmount, "ibWeth balance of ALICE");
  }

  function testCorrectness_IbTokenLiquidationStrat_WhenExecuteLiquidationWithIbTokenMoreThanRequireAmount_ShouldReturnIbTokenToSender()
    external
  {
    // prepare criteria
    address _ibToken = address(ibWeth);
    address _debtToken = address(usdc);
    uint256 _ibTokenIn = 1 ether;
    uint256 _repayAmount = 0.5 ether; // reflect to amountIns[0]
    uint256 _minReceive = 0 ether;

    // _ibTokenTotalSupply = 100 ether
    // _totalTokenWithInterest = 100 ether
    // _requireAmountToWithdraw = 0.5 (amountIns[0]) * 100 / 100 = 0.5 ether
    // to withdraw, amount to withdraw = Min(_requireAmountToWithdraw, _ibTokenIn) = 0.5 ether

    // mock withdrawal amount
    uint256 _expectedWithdrawalAmount = 0.5 ether;
    moneyMarket.setWithdrawalAmount(_expectedWithdrawalAmount);

    // this case will call swapTokensForExactTokens
    uint256 _expectedSwapedAmount = 0.5 ether;

    vm.startPrank(ALICE);
    // transfer ib token to strat
    ibWeth.transfer(address(liquidationStrat), _ibTokenIn);
    liquidationStrat.executeLiquidation(_ibToken, _debtToken, _ibTokenIn, _repayAmount, abi.encode(_minReceive));
    vm.stopPrank();

    // nothing left in strat
    // to check ibToken should not exists on liquidation strat
    assertEq(ibWeth.balanceOf(address(liquidationStrat)), 0, "ibWeth balance of liquidationStrat");
    // to check underlyingToken should swap all
    assertEq(weth.balanceOf(address(liquidationStrat)), 0, "weth balance of liquidationStrat");
    // to check swapped token should be here
    assertEq(usdc.balanceOf(address(liquidationStrat)), 0, "usdc balance of liquidationStrat");

    // to check router work correctly (we can remove this assertion because this is for mock)
    assertEq(usdc.balanceOf(address(router)), _routerUSDCBalance - _expectedSwapedAmount, "usdc balance of router");
    assertEq(usdc.balanceOf(ALICE), _aliceUSDCBalance + _expectedSwapedAmount, "usdc balance of ALICE");

    // to check final ibToken should be corrected
    assertEq(ibWeth.balanceOf(ALICE), _aliceIbTokenBalance - _expectedWithdrawalAmount, "ibWeth balance of ALICE");
  }
}
