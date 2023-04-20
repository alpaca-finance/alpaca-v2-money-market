// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BasePCSV3IbLiquidationForkTest } from "./BasePCSV3IbLiquidationForkTest.sol";
import { PancakeswapV3IbTokenLiquidationStrategy } from "../../../contracts/money-market/PancakeswapV3IbTokenLiquidationStrategy.sol";

// mocks
import { MockERC20 } from "solidity/tests/mocks/MockERC20.sol";

contract PancakeswapV3IbTokenLiquidationStrategy_ExecuteLiquidation is BasePCSV3IbLiquidationForkTest {
  uint256 _aliceIbTokenBalance;
  uint256 _aliceETHBalance;
  uint256 _aliceBTCBBalance;

  function setUp() public override {
    super.setUp();

    // mint ibETH to alice
    ibETH.mint(ALICE, normalizeEther(1 ether, ibETHDecimal));

    moneyMarket.setIbToken(address(ibETH), address(ETH));

    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;
    liquidationStrat.setCallersOk(_callers, true);

    // Set path
    bytes[] memory _paths = new bytes[](1);
    _paths[0] = abi.encodePacked(address(ETH), uint24(2500), address(btcb));
    liquidationStrat.setPaths(_paths);

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
    _aliceIbTokenBalance = ibETH.balanceOf(ALICE);
    _aliceETHBalance = ETH.balanceOf(ALICE);
    _aliceBTCBBalance = btcb.balanceOf(ALICE);

    // _ibTokenTotalSupply = 100 ether
    // _totalTokenWithInterest = 100 ether
    // _requireAmountToWithdraw = 1 (amountIns[0]) * 100 / 100 = 1 ether
    // to withdraw, amount to withdraw = Min(_requireAmountToWithdraw, _ibTokenIn) = 1 ether

    // mock withdrawal amount
    uint256 _expectedIbTokenAmountToWithdraw = normalizeEther(1 ether, ibETHDecimal);
    uint256 _expectedWithdrawalAmount = normalizeEther(1 ether, ETHDecimal);
    moneyMarket.setWithdrawalAmount(_expectedWithdrawalAmount);

    vm.startPrank(ALICE);
    // transfer ib token to strat
    ibETH.transfer(address(liquidationStrat), _ibTokenIn);
    assertEq(ibETH.balanceOf(address(liquidationStrat)), _ibTokenIn, "ibETH balance of liquidationStrat");
    liquidationStrat.executeLiquidation(_ibToken, _debtToken, _ibTokenIn, 0, _minReceive);
    vm.stopPrank();

    // nothing left in strat
    // to check underlyingToken should swap all
    assertEq(ETH.balanceOf(address(liquidationStrat)), 0, "ETH balance of liquidationStrat");

    // to check swapped token should be here
    assertEq(btcb.balanceOf(address(liquidationStrat)), 0, "btcb balance of liquidationStrat");

    // ALICE must get repay token
    assertGt(btcb.balanceOf(ALICE), _aliceBTCBBalance, "btcb balance of ALICE");

    // to check final ibToken should be corrected
    assertEq(ibETH.balanceOf(ALICE), _aliceIbTokenBalance - _expectedIbTokenAmountToWithdraw, "ibETH balance of ALICE");

    // to check final underlying should be not affected
    assertEq(ETH.balanceOf(ALICE), _aliceETHBalance, "ETH balance of ALICE");
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
}
