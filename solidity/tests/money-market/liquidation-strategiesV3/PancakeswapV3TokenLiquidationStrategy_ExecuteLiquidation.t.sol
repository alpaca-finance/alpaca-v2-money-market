// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BasePCSV3LiquidationForkTest } from "./BasePCSV3LiquidationForkTest.sol";
import { PancakeswapV3TokenLiquidationStrategy } from "../../../contracts/money-market/PancakeswapV3TokenLiquidationStrategy.sol";

// mocks
import { MockERC20 } from "solidity/tests/mocks/MockERC20.sol";

contract PancakeswapV3TokenLiquidationStrategy_ExecuteLiquidation is BasePCSV3LiquidationForkTest {
  bytes[] internal paths = new bytes[](1);
  PancakeswapV3TokenLiquidationStrategy internal liquidationStrat;

  function setUp() public override {
    super.setUp();
    liquidationStrat = new PancakeswapV3TokenLiquidationStrategy(address(router), address(pathReader));

    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;
    liquidationStrat.setCallersOk(_callers, true);

    // Set path
    paths[0] = abi.encodePacked(address(ETH), uint24(2500), address(btcb));
    pathReader.setPaths(paths);

    // mint ETH to ALICE
    vm.startPrank(BSC_TOKEN_OWNER);
    ETH.mint(normalizeEther(10 ether, ETHDecimal)); // mint to mm
    ETH.transfer(address(ALICE), normalizeEther(10 ether, ETHDecimal));
    vm.stopPrank();
  }

  function testCorrectness_LiquidationStratV3_WhenExecuteLiquidation_ShouldWork() external {
    address _collatToken = address(ETH);
    address _debtToken = address(btcb);
    uint256 _collatAmountIn = normalizeEther(1 ether, ETHDecimal);

    // state before execution
    uint256 _aliceBTCBBalanceBefore = btcb.balanceOf(ALICE);

    // expected repay amount out after swap
    (uint256 _expectedAmountOut, , , ) = quoterV2.quoteExactInput(paths[0], _collatAmountIn);

    vm.startPrank(ALICE);
    MockERC20(_collatToken).transfer(address(liquidationStrat), _collatAmountIn);
    liquidationStrat.executeLiquidation(_collatToken, _debtToken, _collatAmountIn, 0, 0, "");
    vm.stopPrank();

    uint256 _aliceBTCBBalanceAfter = btcb.balanceOf(ALICE);

    // nothing left in strat
    assertEq(ETH.balanceOf(address(liquidationStrat)), 0, "ETH balance of strat");
    assertEq(btcb.balanceOf(address(liquidationStrat)), 0, "BTCB balance of strat");

    // caller (ALICE) must get repay token amount
    assertEq(_aliceBTCBBalanceAfter, _aliceBTCBBalanceBefore + _expectedAmountOut, "BTCB balance of money market");
  }

  function testCorrectness_WhenInjectCollatToStrat_ExecuteLiquidationV3_ShouldTransferCollatAmountBackCorrectly()
    external
  {
    address _collatToken = address(ETH);
    address _debtToken = address(btcb);

    uint256 _collatAmount = normalizeEther(1 ether, ETHDecimal);
    // expected repay amount
    (uint256 _expectedAmountOut, , , ) = quoterV2.quoteExactInput(paths[0], _collatAmount);

    uint256 _injectAmount = normalizeEther(1 ether, ETHDecimal);
    vm.startPrank(BSC_TOKEN_OWNER);
    ETH.mint(_collatAmount + _injectAmount);
    ETH.transfer(address(liquidationStrat), _collatAmount + _injectAmount);
    vm.stopPrank();

    vm.prank(ALICE);
    liquidationStrat.executeLiquidation(_collatToken, _debtToken, _collatAmount, 0, 0, "");

    // injected collat left in strat
    assertEq(ETH.balanceOf(address(liquidationStrat)), _injectAmount, "ETH balance of strat");
    assertEq(btcb.balanceOf(address(liquidationStrat)), 0, "btcb balance of strat");

    assertEq(btcb.balanceOf(address(ALICE)), _expectedAmountOut, "btcb balance of callers");
  }

  function testRevert_WhenNonCallersCallExecuteLiquidation_ShouldRevert() external {
    address _collatToken = address(ETH);
    address _debtToken = address(btcb);

    vm.prank(BOB);
    vm.expectRevert(
      abi.encodeWithSelector(
        PancakeswapV3TokenLiquidationStrategy.PancakeswapV3TokenLiquidationStrategy_Unauthorized.selector
      )
    );
    liquidationStrat.executeLiquidation(
      _collatToken,
      _debtToken,
      normalizeEther(1 ether, ETHDecimal),
      normalizeEther(1 ether, btcbDecimal),
      0,
      ""
    );
  }

  function testRevert_WhenExecuteLiquidationOnNonExistingPath() external {
    address _collatToken = address(btcb);
    address _debtToken = address(cake);

    vm.prank(ALICE);
    vm.expectRevert();
    liquidationStrat.executeLiquidation(
      _collatToken,
      _debtToken,
      normalizeEther(1 ether, btcbDecimal),
      normalizeEther(1 ether, cakeDecimal),
      0,
      ""
    );
  }

  function testCorrectness_WhenLiquidationOnMultiHop_ShouldWork() external {
    address _collatToken = address(ETH);
    address _debtToken = address(usdt);
    uint256 _collatTokenAmountIn = normalizeEther(1 ether, ETHDecimal);
    uint256 _minReceive = 0;

    // set withdrawal amount
    uint256 _expectedWithdrawalAmount = normalizeEther(1 ether, ETHDecimal);
    moneyMarket.setWithdrawalAmount(_expectedWithdrawalAmount);

    // state before execution
    uint256 _aliceETHBalanceBefore = ETH.balanceOf(ALICE);
    uint256 _aliceBTCBBalanceBefore = btcb.balanceOf(ALICE);
    uint256 _aliceUSDTBalanceBefore = usdt.balanceOf(ALICE);

    // set multi-hop path ETH => btcb => usdt
    bytes[] memory _paths = new bytes[](1);
    _paths[0] = abi.encodePacked(address(ETH), uint24(2500), address(btcb), uint24(500), address(usdt));
    pathReader.setPaths(_paths);

    // transfer collat to to strat
    vm.startPrank(ALICE);
    ETH.transfer(address(liquidationStrat), _collatTokenAmountIn);
    // expect amount out 2 hop expect btcb, expect usdt
    bytes memory _ETHToBtcbPath = abi.encodePacked(address(ETH), uint24(2500), address(btcb));
    (uint256 _expectedBTCBOut, , , ) = quoterV2.quoteExactInput(_ETHToBtcbPath, _collatTokenAmountIn);

    bytes memory _BtcbToUsdtPath = abi.encodePacked(address(btcb), uint24(500), address(usdt));
    (uint256 _expectedUSDTOut, , , ) = quoterV2.quoteExactInput(_BtcbToUsdtPath, _expectedBTCBOut);

    liquidationStrat.executeLiquidation(_collatToken, _debtToken, _collatTokenAmountIn, 0, _minReceive, "");

    uint256 _aliceETHBalanceAfter = ETH.balanceOf(ALICE);
    uint256 _aliceBTCBBalanceAfter = btcb.balanceOf(ALICE);
    uint256 _aliceUSDTBalanceAfter = usdt.balanceOf(ALICE);

    // nothing left in strat
    assertEq(ETH.balanceOf(address(liquidationStrat)), 0, "ETH balance of strat");
    assertEq(btcb.balanceOf(address(liquidationStrat)), 0, "btcb balance of strat");
    assertEq(usdt.balanceOf(address(liquidationStrat)), 0, "usdt balance of strat");

    // eth of alice must not effect
    assertEq(_aliceETHBalanceAfter, _aliceETHBalanceBefore - _collatTokenAmountIn, "ETH balance of ALICE");

    // btcb of alice (middle hop) must not left
    assertEq(_aliceBTCBBalanceAfter, _aliceBTCBBalanceBefore, "BTCB balance of ALICE");

    // huge amount of collat token will cause the revert, since the tick would be changed
    // repay token (usdt) of alice must increase
    assertEq(_aliceUSDTBalanceAfter, _aliceUSDTBalanceBefore + _expectedUSDTOut, "USDT balance of ALICE");
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
    PancakeswapV3TokenLiquidationStrategy.WithdrawParam[]
      memory _withdrawParams = new PancakeswapV3TokenLiquidationStrategy.WithdrawParam[](2);
    _withdrawParams[0] = PancakeswapV3TokenLiquidationStrategy.WithdrawParam(
      ALICE,
      address(_token0),
      _withdrawToken0Amount
    );
    _withdrawParams[1] = PancakeswapV3TokenLiquidationStrategy.WithdrawParam(
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

    PancakeswapV3TokenLiquidationStrategy.WithdrawParam[]
      memory _withdrawParams = new PancakeswapV3TokenLiquidationStrategy.WithdrawParam[](1);
    _withdrawParams[0] = PancakeswapV3TokenLiquidationStrategy.WithdrawParam(ALICE, address(_token), _withdrawAmount);

    // prank to BOB and call withdraw
    vm.startPrank(BOB);
    vm.expectRevert("Ownable: caller is not the owner");
    liquidationStrat.withdraw(_withdrawParams);
  }
}
