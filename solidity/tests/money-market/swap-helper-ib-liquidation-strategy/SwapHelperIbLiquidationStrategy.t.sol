// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { DSTest } from "solidity/tests/base/DSTest.sol";
import "../../utils/Components.sol";

import { SwapHelperIbLiquidationStrategy } from "solidity/contracts/money-market/SwapHelperIbLiquidationStrategy.sol";
import { SwapHelper } from "solidity/contracts/swap-helper/SwapHelper.sol";

import { IERC20 } from "solidity/contracts/interfaces/IERC20.sol";
import { IPancakeSwapRouterV3 } from "solidity/contracts/money-market/interfaces/IPancakeSwapRouterV3.sol";
import { IPancakeRouter02 } from "solidity/contracts/money-market/interfaces/IPancakeRouter02.sol";
import { ISwapHelper } from "solidity/contracts/interfaces/ISwapHelper.sol";

import { MockMoneyMarket } from "../../mocks/MockMoneyMarket.sol";

contract SwapHelperIbLiquidationStrategyTest is DSTest, StdUtils, StdAssertions, StdCheats {
  VM internal constant vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

  SwapHelperIbLiquidationStrategy public liquidationStrategy;
  SwapHelper public swapHelper;
  MockMoneyMarket public mockMoneyMarket;

  IERC20 constant wbnb = IERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
  address constant mockIbWBNB = address(1234);
  IERC20 constant usdt = IERC20(0x55d398326f99059fF775485246999027B3197955);
  IERC20 constant busd = IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
  address constant routerV2 = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
  address constant routerV3 = 0x1b81D678ffb9C0263b24A97847620C99d213eB14;

  function setUp() public {
    vm.createSelectFork("bsc_mainnet", 27_280_390);

    // Prepare mock money market
    mockMoneyMarket = new MockMoneyMarket();
    mockMoneyMarket.setIbToken(mockIbWBNB, address(wbnb));
    deal(address(wbnb), address(mockMoneyMarket), 100 ether);

    // Deploy swap helper
    swapHelper = new SwapHelper();

    // Prepare liquidation strategy
    liquidationStrategy = new SwapHelperIbLiquidationStrategy(
      address(swapHelper),
      address(mockMoneyMarket),
      address(busd)
    );
    address[] memory _callers = new address[](1);
    _callers[0] = address(this);
    liquidationStrategy.setCallersOk(_callers, true);
  }

  function _setSwapHelperSwapInfoPCSV3(address _tokenIn, address _tokenOut, bytes memory _path) internal {
    // prepare origin swap calldata
    IPancakeSwapRouterV3.ExactInputParams memory _params = IPancakeSwapRouterV3.ExactInputParams({
      path: _path,
      recipient: address(0),
      deadline: type(uint256).max,
      amountIn: 0,
      amountOutMinimum: 0
    });
    bytes memory _calldata = abi.encodeCall(IPancakeSwapRouterV3.exactInput, _params);
    // set swap info
    ISwapHelper.SwapInfo memory _swapInfo = ISwapHelper.SwapInfo({
      swapCalldata: _calldata,
      router: routerV3,
      amountInOffset: 128 + 4,
      toOffset: 64 + 4,
      minAmountOutOffset: 160 + 4
    });
    swapHelper.setSwapInfo(_tokenIn, _tokenOut, _swapInfo);
  }

  function _setSwapHelperSwapInfoPCSV2(address _tokenIn, address _tokenOut, address[] memory _path) internal {
    // prepare origin swap calldata
    bytes memory _calldata = abi.encodeCall(
      IPancakeRouter02.swapExactTokensForTokens,
      (1, 2, _path, address(3), type(uint256).max)
    );
    // set swap info
    ISwapHelper.SwapInfo memory _swapInfo = ISwapHelper.SwapInfo({
      swapCalldata: _calldata,
      router: routerV2,
      amountInOffset: swapHelper.search(_calldata, 1),
      toOffset: swapHelper.search(_calldata, address(3)),
      minAmountOutOffset: swapHelper.search(_calldata, 2)
    });
    swapHelper.setSwapInfo(_tokenIn, _tokenOut, _swapInfo);
  }

  function testRevert_ExecuteLiquidation_CallerIsNotWhitelisted() public {
    vm.prank(address(1234));
    vm.expectRevert(abi.encodeWithSignature("SwapHelperIbTokenLiquidationStrategy_Unauthorized()"));
    liquidationStrategy.executeLiquidation(mockIbWBNB, address(usdt), 1 ether, 0, 0);
  }

  function testRevert_ExecuteLiquidation_RepayTokenIsSameWithUnderlyingToken() public {
    vm.expectRevert(
      abi.encodeWithSignature("SwapHelperIbTokenLiquidationStrategy_RepayTokenIsSameWithUnderlyingToken()")
    );
    liquidationStrategy.executeLiquidation(mockIbWBNB, address(wbnb), 1 ether, 0, 0);
  }

  function testCorrectness_ExecuteLiquidation_SwapV3() public {
    // Scenario: Liquidate 1 ibwbnb (1 ibwbnb = 1 wbnb) for usdt via pcs v3 through busd as bridge token

    // Setup
    _setSwapHelperSwapInfoPCSV3(
      address(wbnb),
      address(busd),
      abi.encodePacked(address(wbnb), uint24(500), address(busd))
    );
    _setSwapHelperSwapInfoPCSV3(
      address(busd),
      address(usdt),
      abi.encodePacked(address(busd), uint24(100), address(usdt))
    );
    mockMoneyMarket.setWithdrawalAmount(1 ether);

    uint256 usdtBefore = usdt.balanceOf(address(this));
    // Execute liquidation
    liquidationStrategy.executeLiquidation(mockIbWBNB, address(usdt), 1 ether, 0, 0);
    // Assertions
    // - sender usdt increase (wbnb is swapped for usdt)
    assertGt(usdt.balanceOf(address(this)), usdtBefore);
    // Invariants
    // - no token left in strategy
    assertEq(wbnb.balanceOf(address(liquidationStrategy)), 0);
    assertEq(busd.balanceOf(address(liquidationStrategy)), 0);
    assertEq(usdt.balanceOf(address(liquidationStrategy)), 0);
  }

  function testCorrectness_ExecuteLiquidation_SwapV2() public {
    // Scenario: Liquidate 1 ibwbnb (1 ibwbnb = 1 wbnb) for usdt via pcs v2 through busd as bridge token

    // Setup
    address[] memory _pathV2 = new address[](2);
    _pathV2[0] = address(wbnb);
    _pathV2[1] = address(busd);
    _setSwapHelperSwapInfoPCSV2(address(wbnb), address(busd), _pathV2);
    mockMoneyMarket.setWithdrawalAmount(1 ether);
    _pathV2 = new address[](2);
    _pathV2[0] = address(busd);
    _pathV2[1] = address(usdt);
    _setSwapHelperSwapInfoPCSV2(address(busd), address(usdt), _pathV2);
    mockMoneyMarket.setWithdrawalAmount(1 ether);

    uint256 usdtBefore = usdt.balanceOf(address(this));
    // Execute liquidation
    liquidationStrategy.executeLiquidation(mockIbWBNB, address(usdt), 1 ether, 0, 0);
    // Assertions
    // - sender usdt increase (wbnb is swapped for usdt)
    assertGt(usdt.balanceOf(address(this)), usdtBefore);
    // Invariants
    // - no token left in strategy
    assertEq(wbnb.balanceOf(address(liquidationStrategy)), 0);
    assertEq(busd.balanceOf(address(liquidationStrategy)), 0);
    assertEq(usdt.balanceOf(address(liquidationStrategy)), 0);
  }

  function testRevert_ExecuteLiquidation_SwapFailed() public {
    // Set bad swap info so swap should failed
    _setSwapHelperSwapInfoPCSV3(
      address(wbnb),
      address(busd),
      abi.encodePacked(address(wbnb), uint24(99999), address(busd))
    );

    vm.expectRevert(abi.encodeWithSignature("SwapHelperIbTokenLiquidationStrategy_SwapFailed()"));
    liquidationStrategy.executeLiquidation(mockIbWBNB, address(usdt), 1 ether, 0, 0);
  }

  function testRevert_SetBridgeToken_CallerIsNotOwner() public {
    vm.prank(address(1234));
    vm.expectRevert("Ownable: caller is not the owner");
    liquidationStrategy.setBridgeToken(address(1234));
  }

  function testCorrectness_SetBridgeToken() public {
    liquidationStrategy.setBridgeToken(address(1234));
    assertEq(liquidationStrategy.bridgeToken(), address(1234));
  }

  function testRevert_SetCallersOk_CallerIsNotOwner() public {
    vm.prank(address(1234));
    vm.expectRevert("Ownable: caller is not the owner");
    liquidationStrategy.setCallersOk(new address[](0), true);
  }

  function testCorrectness_SetCallersOk() public {
    address[] memory callers = new address[](1);
    callers[0] = address(1234);
    liquidationStrategy.setCallersOk(callers, true);

    assertEq(liquidationStrategy.callersOk(address(1234)), true);
  }

  function testRevert_Withdraw_CallerIsNotOwner() public {
    vm.prank(address(1234));
    vm.expectRevert("Ownable: caller is not the owner");
    SwapHelperIbLiquidationStrategy.WithdrawParam[] memory params = new SwapHelperIbLiquidationStrategy.WithdrawParam[](
      1
    );
    params[0] = SwapHelperIbLiquidationStrategy.WithdrawParam({ to: address(1234), token: address(1234), amount: 0 });
    liquidationStrategy.withdraw(params);
  }

  function testCorrectness_Withdraw() public {
    deal(address(wbnb), address(liquidationStrategy), 1 ether);
    deal(address(usdt), address(liquidationStrategy), 1 ether);

    uint256 wbnbBefore = wbnb.balanceOf(address(this));
    uint256 usdtBefore = usdt.balanceOf(address(this));

    SwapHelperIbLiquidationStrategy.WithdrawParam[] memory params = new SwapHelperIbLiquidationStrategy.WithdrawParam[](
      2
    );
    params[0] = SwapHelperIbLiquidationStrategy.WithdrawParam({
      to: address(this),
      token: address(wbnb),
      amount: 1 ether
    });
    params[1] = SwapHelperIbLiquidationStrategy.WithdrawParam({
      to: address(this),
      token: address(usdt),
      amount: 1 ether
    });
    liquidationStrategy.withdraw(params);

    assertEq(wbnb.balanceOf(address(this)), wbnbBefore + 1 ether);
    assertEq(usdt.balanceOf(address(this)), usdtBefore + 1 ether);
  }
}
