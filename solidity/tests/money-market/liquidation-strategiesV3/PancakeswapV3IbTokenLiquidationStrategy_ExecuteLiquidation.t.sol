// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BasePCSV3IbLiquidationForkTest } from "./BasePCSV3IbLiquidationForkTest.sol";
import { PancakeswapV3IbTokenLiquidationStrategy } from "../../../contracts/money-market/PancakeswapV3IbTokenLiquidationStrategy.sol";

// interfaces
import { IV3SwapRouter } from "solidity/contracts/money-market/interfaces/IV3SwapRouter.sol";
import { IPancakeV3Factory } from "solidity/contracts/money-market/interfaces/IPancakeV3Factory.sol";
import { IBEP20 } from "solidity/contracts/money-market/interfaces/IBEP20.sol";

// mocks
import { MockRouter } from "../../mocks/MockRouter.sol";
import { MockLPToken } from "../../mocks/MockLPToken.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";
import { MockMoneyMarket } from "../../mocks/MockMoneyMarket.sol";
import { MockMoneyMarketV3 } from "../../mocks/MockMoneyMarketV3.sol";

// ib Setup
import { IAdminFacet } from "solidity/contracts/money-market/interfaces/IAdminFacet.sol";
import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";
import { InterestBearingToken } from "../../../contracts/money-market/InterestBearingToken.sol";

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

    vm.startPrank(0xF68a4b64162906efF0fF6aE34E2bB1Cd42FEf62d);
    ETH.mint(normalizeEther(10 ether, ETHDecimal)); // mint to mm
    ETH.transfer(address(moneyMarket), normalizeEther(10 ether, ETHDecimal));
    btcb.mint(normalizeEther(10 ether, btcbDecimal)); // mint to mm
    btcb.transfer(address(moneyMarket), normalizeEther(10 ether, btcbDecimal));
    vm.stopPrank();
  }

  function testRevert_WhenExecuteLiquidationV3_PathConfigNotFound() external {
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

  // expect ibWeth => ETH => btcb
  function testCorrectness_WhenExecuteIbTokenLiquiationStratV345_ShouldWork() external {
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
    // NOTE: ibETH was not burnt. Since the MockMoneyMarketV3 has no onWithdraw
    // to check ibToken should not exists on liquidation strat
    // assertEq(ibETH.balanceOf(address(liquidationStrat)), 0, "ibETH balance of liquidationStrat");

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
