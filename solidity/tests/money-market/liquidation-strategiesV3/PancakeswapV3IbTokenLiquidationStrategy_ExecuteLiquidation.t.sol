// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseTest, console } from "../../base/BaseTest.sol";
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

contract PancakeswapV3IbTokenLiquidationStrategy_ExecuteLiquidation is BaseTest {
  string internal BSC2_URL_RPC = "https://bsc-dataseed2.ninicoin.io";

  IPancakeV3Factory internal PANCAKE_V3_FACTORY = IPancakeV3Factory(0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865);
  IV3SwapRouter internal router = IV3SwapRouter(0x13f4EA83D0bd40E75C8222255bc855a974568Dd4);
  PancakeswapV3IbTokenLiquidationStrategy internal liquidationStrat;
  MockMoneyMarketV3 internal moneyMarket;

  uint256 _routerUSDCBalance;
  uint256 _aliceBTCBBalance;
  uint256 _aliceWETHBalance;
  uint256 _aliceIbTokenBalance;

  IBEP20 constant ETH = IBEP20(0x2170Ed0880ac9A755fd29B2688956BD959F933F8);
  IBEP20 constant btcb = IBEP20(0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c);
  MockERC20 internal ibETH;

  uint256 internal ETHDecimal;
  uint256 internal btcbDecimal;
  uint256 internal ibETHDecimal;

  function setUp() public virtual {
    vm.selectFork(vm.createFork(BSC2_URL_RPC));
    vm.rollFork(27_280_390); // block 27280390

    ibETH = deployMockErc20("ibETH", "ibETH", 18);

    ETHDecimal = ETH.decimals();
    btcbDecimal = btcb.decimals();
    ibETHDecimal = ibETH.decimals();

    moneyMarket = new MockMoneyMarketV3();
    moneyMarket.setIbToken(address(ibETH), address(ETH));
    liquidationStrat = new PancakeswapV3IbTokenLiquidationStrategy(
      address(router),
      address(moneyMarket),
      address(PANCAKE_V3_FACTORY)
    );
    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;
    liquidationStrat.setCallersOk(_callers, true);

    // Set path
    bytes[] memory _paths = new bytes[](1);
    _paths[0] = abi.encodePacked(address(ETH), uint24(2500), address(btcb));
    liquidationStrat.setPaths(_paths);

    vm.startPrank(0xF68a4b64162906efF0fF6aE34E2bB1Cd42FEf62d);
    ETH.mint(normalizeEther(10 ether, wethDecimal)); // mint to mm
    ETH.transfer(address(moneyMarket), normalizeEther(10 ether, wethDecimal));
    btcb.mint(normalizeEther(10 ether, wethDecimal)); // mint to mm
    btcb.transfer(address(moneyMarket), normalizeEther(10 ether, wethDecimal));
    vm.stopPrank();
  }

  function testRevert_WhenExecuteLiquidationV3_PathConfigNotFound() external {
    vm.prank(address(ALICE));
    vm.expectRevert(
      abi.encodeWithSelector(
        PancakeswapV3IbTokenLiquidationStrategy.PancakeswapV3IbTokenLiquidationStrategy_PathConfigNotFound.selector,
        [address(ETH), address(btc)]
      )
    );
    liquidationStrat.executeLiquidation(
      address(ibETH),
      address(btc),
      normalizeEther(1 ether, ibETHDecimal),
      normalizeEther(1 ether, btcDecimal),
      0
    );
  }

  // expect ibWeth => ETH => btcb
  function testCorrectness_WhenExecuteIbTokenLiquiationStratV3_ShouldWork() external {
    // prepare criteria
    address _ibToken = address(ibETH);
    address _debtToken = address(btcb);
    uint256 _ibTokenIn = normalizeEther(1 ether, ibETHDecimal);
    // uint256 _repayAmount = normalizeEther(1 ether, btcbDecimal); // reflect to amountIns[0]
    uint256 _minReceive = 0;

    // mint ibETH to alice
    ibETH.mint(ALICE, normalizeEther(1 ether, ibETHDecimal));

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

    // to check router work correctly (we can remove this assertion because this is for mock)
    // assertEq(btcb.balanceOf(address(router)), _routerUSDCBalance - _expectedSwapedAmount, "usdc balance of router");
    assertGt(btcb.balanceOf(ALICE), _aliceBTCBBalance, "btcb balance of ALICE");

    // to check final ibToken should be corrected
    // assertEq(ibETH.balanceOf(ALICE), _aliceIbTokenBalance - _expectedIbTokenAmountToWithdraw, "ibETH balance of ALICE");
    // to check final underlying should be not affected

    // assertEq(ETH.balanceOf(ALICE), _aliceWETHBalance, "weth balance of ALICE");
  }
}
