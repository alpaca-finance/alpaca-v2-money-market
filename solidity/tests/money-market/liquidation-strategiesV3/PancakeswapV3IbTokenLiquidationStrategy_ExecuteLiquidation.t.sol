// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BasePCSV3LiquidationForkTest, console } from "./BasePCSV3LiquidationForkTest.sol";
import { PancakeswapV3IbTokenLiquidationStrategy } from "../../../contracts/money-market/PancakeswapV3IbTokenLiquidationStrategy.sol";

// mocks
import { MockERC20 } from "solidity/tests/mocks/MockERC20.sol";

contract PancakeswapV3IbTokenLiquidationStrategy_ExecuteLiquidation is BasePCSV3LiquidationForkTest {
  bytes[] internal paths = new bytes[](1);

  function setUp() public override {
    super.setUp();

    // mint ibETH to alice
    ibETH.mint(ALICE, normalizeEther(1 ether, ibETHDecimal));

    moneyMarket.setIbToken(address(ibETH), address(ETH));

    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;
    liquidationStrat.setCallersOk(_callers, true);

    // Set path
    paths[0] = abi.encodePacked(address(ETH), uint24(2500), address(btcb));
    liquidationStrat.setPaths(paths);

    vm.startPrank(BSC_TOKEN_OWNER);
    ETH.mint(normalizeEther(10 ether, ETHDecimal)); // mint to mm
    ETH.transfer(address(moneyMarket), normalizeEther(10 ether, ETHDecimal));
    btcb.mint(normalizeEther(10 ether, btcbDecimal)); // mint to mm
    btcb.transfer(address(moneyMarket), normalizeEther(10 ether, btcbDecimal));
    vm.stopPrank();
  }

  function testRevert_WhenThereIsNoConfiguredPath_ShouldRevert() external {
    vm.prank(address(ALICE));
    vm.expectRevert(
      abi.encodeWithSelector(
        PancakeswapV3IbTokenLiquidationStrategy.PancakeswapV3IbTokenLiquidationStrategy_PathConfigNotFound.selector,
        [address(ETH), address(usdt)]
      )
    );
    liquidationStrat.executeLiquidation(
      address(ibETH),
      address(usdt),
      normalizeEther(1 ether, ibETHDecimal),
      normalizeEther(1 ether, usdtDecimal),
      0
    );
  }

  function testRevert_WhenNonOwnerExecuteLiquidationV3_ShouldRevert() external {
    // prepare criteria
    address _ibToken = address(ibETH);
    address _debtToken = address(btcb);
    uint256 _ibTokenIn = normalizeEther(1 ether, ibETHDecimal);
    uint256 _minReceive = 0;

    ibETH.mint(BOB, normalizeEther(1 ether, ibETHDecimal));
    vm.startPrank(BOB);
    ibETH.transfer(address(liquidationStrat), _ibTokenIn);
    vm.expectRevert(
      abi.encodeWithSelector(
        PancakeswapV3IbTokenLiquidationStrategy.PancakeswapV3IbTokenLiquidationStrategy_Unauthorized.selector
      )
    );
    liquidationStrat.executeLiquidation(_ibToken, _debtToken, _ibTokenIn, 0, _minReceive);
    vm.stopPrank();
  }

  // expect ibWeth => ETH => btcb
  function testCorrectness_WhenExecuteIbTokenLiquiationStratV3_ShouldWork() external {
    // prepare criteria
    address _ibToken = address(ibETH);
    address _debtToken = address(btcb);
    uint256 _ibTokenIn = normalizeEther(1 ether, ibETHDecimal);
    uint256 _minReceive = 0;

    // state before execution
    uint256 _aliceIbTokenBalanceBefore = ibETH.balanceOf(ALICE);
    uint256 _aliceETHBalanceBefore = ETH.balanceOf(ALICE);
    uint256 _aliceBTCBBalanceBefore = btcb.balanceOf(ALICE);

    // all ib token will be swapped (no ib left in liquidationStrat)

    // mock withdrawal amount
    uint256 _expectedIbTokenAmountToWithdraw = normalizeEther(1 ether, ibETHDecimal);
    uint256 _expectedWithdrawalAmount = normalizeEther(1 ether, ETHDecimal);
    moneyMarket.setWithdrawalAmount(_expectedWithdrawalAmount);

    // expect amount out
    (uint256 _expectedAmountOut, , , ) = quoterV2.quoteExactInput(paths[0], _ibTokenIn);

    vm.startPrank(ALICE);
    // transfer ib token to strat
    ibETH.transfer(address(liquidationStrat), _ibTokenIn);
    assertEq(ibETH.balanceOf(address(liquidationStrat)), _ibTokenIn, "ibETH balance of liquidationStrat");
    liquidationStrat.executeLiquidation(_ibToken, _debtToken, _ibTokenIn, 0, _minReceive);
    vm.stopPrank();

    // ALICE's balance after execution
    uint256 _aliceBTCBBalanceAfter = btcb.balanceOf(ALICE);

    // nothing left in strat
    // to check underlyingToken should swap all
    assertEq(ETH.balanceOf(address(liquidationStrat)), 0, "ETH balance of liquidationStrat");

    // to check swapped token should be here
    assertEq(btcb.balanceOf(address(liquidationStrat)), 0, "btcb balance of liquidationStrat");

    // to check swap work correctly
    assertEq(_aliceBTCBBalanceAfter, _aliceBTCBBalanceBefore + _expectedAmountOut, "btcb balance of ALICE");

    // to check final ibToken should be corrected
    assertEq(
      ibETH.balanceOf(ALICE),
      _aliceIbTokenBalanceBefore - _expectedIbTokenAmountToWithdraw,
      "ibETH balance of ALICE"
    );

    // to check final underlying should be not affected
    assertEq(ETH.balanceOf(ALICE), _aliceETHBalanceBefore, "ETH balance of ALICE");
  }

  function testRevert_WhenExecuteIbTokenLiquiationStratV3AndUnderlyingTokenAndRepayTokenAreSame() external {
    // prepare criteria
    address _ibToken = address(ibETH);
    address _debtToken = address(ETH);
    uint256 _ibTokenIn = normalizeEther(1 ether, ibETHDecimal);
    uint256 _minReceive = 0 ether;

    // _ibTokenTotalSupply = 100 ether
    // _totalTokenWithInterest = 100 ether
    // _requireAmountToWithdraw = repay amount = 1 ether
    // to withdraw, amount to withdraw = Min(_requireAmountToWithdraw, _ibTokenIn) = 1 ether

    vm.startPrank(ALICE);
    // transfer ib token to strat
    ibETH.transfer(address(liquidationStrat), _ibTokenIn);
    vm.expectRevert(
      abi.encodeWithSelector(
        PancakeswapV3IbTokenLiquidationStrategy
          .PancakeswapV3IbTokenLiquidationStrategy_RepayTokenIsSameWithUnderlyingToken
          .selector
      )
    );
    liquidationStrat.executeLiquidation(_ibToken, _debtToken, _ibTokenIn, 0, _minReceive);
    vm.stopPrank();
  }

  function testCorrectness_WhenLiduidateMultiHopIbToken_ShouldWork() external {
    address _ibToken = address(ibETH);
    address _debtToken = address(usdt);
    uint256 _ibTokenAmountIn = normalizeEther(1 ether, ibETHDecimal);
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
    liquidationStrat.setPaths(_paths);

    // transfer ib to strat
    vm.startPrank(ALICE);
    ibETH.transfer(address(liquidationStrat), _ibTokenAmountIn);
    // expect amount out 2 hop expect btcb, expect usdt
    bytes memory _ETHToBtcbPath = abi.encodePacked(address(ETH), uint24(2500), address(btcb));
    (uint256 _expectedBTCBOut, , , ) = quoterV2.quoteExactInput(_ETHToBtcbPath, _ibTokenAmountIn);

    bytes memory _BtcbToUsdtPath = abi.encodePacked(address(btcb), uint24(500), address(usdt));
    (uint256 _expectedUSDTOut, , , ) = quoterV2.quoteExactInput(_BtcbToUsdtPath, _expectedBTCBOut);

    liquidationStrat.executeLiquidation(_ibToken, _debtToken, _ibTokenAmountIn, 0, _minReceive);

    uint256 _aliceETHBalanceAfter = ETH.balanceOf(ALICE);
    uint256 _aliceBTCBBalanceAfter = btcb.balanceOf(ALICE);
    uint256 _aliceUSDTBalanceAfter = usdt.balanceOf(ALICE);

    // nothing left in strat
    assertEq(ETH.balanceOf(address(liquidationStrat)), 0, "ETH balance of strat");
    assertEq(btcb.balanceOf(address(liquidationStrat)), 0, "btcb balance of strat");
    assertEq(usdt.balanceOf(address(liquidationStrat)), 0, "usdt balance of strat");

    // eth of alice must not effect
    assertEq(_aliceETHBalanceAfter, _aliceETHBalanceBefore, "ETH balance of ALICE");

    // btcb of alice (middle hop) must not left
    assertEq(_aliceBTCBBalanceAfter, _aliceBTCBBalanceBefore, "BTCB balance of ALICE");

    // huge amount of collat token will cause the revert, since the tick would be changed
    // repay token (usdt) of alice must increase
    assertEq(_aliceUSDTBalanceAfter, _aliceUSDTBalanceBefore + _expectedUSDTOut, "USDT balance of ALICE");
  }
}
