// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseFork } from "./BaseFork.sol";

// implementation
import { OracleMedianizer } from "solidity/contracts/oracle/OracleMedianizer.sol";

// interfaces
import { ISmartTreasury } from "solidity/contracts/interfaces/ISmartTreasury.sol";
import { IPancakeSwapRouterV3 } from "solidity/contracts/money-market/interfaces/IPancakeSwapRouterV3.sol";
import { IERC20 } from "solidity/contracts/money-market/interfaces/IERC20.sol";
import { IPriceOracle } from "solidity/contracts/oracle/interfaces/IPriceOracle.sol";
import { IUniSwapV2PathReader } from "../../contracts/reader/interfaces/IUniSwapV2PathReader.sol";
import { IUniSwapV3PathReader } from "solidity/contracts/reader/interfaces/IUniSwapV3PathReader.sol";

contract SmartTreasury_Distribute is BaseFork {
  struct CacheState {
    uint256 _rev;
    uint256 _dev;
    uint256 _burn;
  }

  function setUp() public override {
    super.setUp();

    // setup whitelisted caller
    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;
    vm.startPrank(DEPLOYER);
    smartTreasury.setWhitelistedCallers(_callers, true);
    // setup revenue token, alloc points and treasury address
    smartTreasury.setRevenueToken(address(usdt));
    smartTreasury.setAllocPoints(3333, 3333, 3334);
    smartTreasury.setTreasuryAddresses(REVENUE_TREASURY, DEV_TREASURY, BURN_TREASURY);
    smartTreasury.setSlippageToleranceBps(100);
    vm.stopPrank();
  }

  function testCorrectness_CallDistribute_ShouldWork() external {
    // state before distribution
    uint256 _USDTrevenueBalanceBefore = IERC20(address(usdt)).balanceOf(REVENUE_TREASURY);
    uint256 _WBNBdevBalanceBefore = IERC20(address(wbnb)).balanceOf(DEV_TREASURY);
    uint256 _WBNBburnBalanceBefore = IERC20(address(wbnb)).balanceOf(BURN_TREASURY);

    // top up wbnb to smart treasury
    deal(address(wbnb), address(smartTreasury), 30 ether);

    address[] memory _tokens = new address[](1);
    _tokens[0] = address(wbnb);
    vm.prank(ALICE);
    smartTreasury.distribute(_tokens);

    // expect amount in usdt
    (uint256 _expectedAmountOut, , , ) = quoterV2.quoteExactInput(
      abi.encodePacked(address(wbnb), uint24(500), address(usdt)),
      10 ether
    );

    // state after distribute
    uint256 _USDTrevenueBalanceAfter = IERC20(address(usdt)).balanceOf(REVENUE_TREASURY);
    uint256 _WBNBdevBalanceAfter = IERC20(address(wbnb)).balanceOf(DEV_TREASURY);
    uint256 _WBNBburnBalanceAfter = IERC20(address(wbnb)).balanceOf(BURN_TREASURY);

    // rev treasury (USDT)
    assertCloseBps(_USDTrevenueBalanceAfter, _USDTrevenueBalanceBefore + _expectedAmountOut, 100);
    // dev treasury (WBNB)
    assertCloseBps(_WBNBdevBalanceAfter, _WBNBdevBalanceBefore + 10 ether, 100);
    // burn treasury (WBNB)
    assertCloseBps(_WBNBburnBalanceAfter, _WBNBburnBalanceBefore + 10 ether, 100);

    // Smart treasury must have nothing
    uint256 _WBNBSmartTreasuryBalanceAfter = IERC20(address(wbnb)).balanceOf(address(smartTreasury));
    assertEq(_WBNBSmartTreasuryBalanceAfter, 0, "Smart treasury balance (WBNB)");
  }

  function testRevert_UnauthorizedCallDistribute_ShouldRevert() external {
    // top up wbnb to smart treasury
    deal(address(wbnb), address(smartTreasury), 30 ether);
    uint256 _WBNBTreasuryBalanceBefore = IERC20(address(wbnb)).balanceOf(address(smartTreasury));

    address[] memory _tokens = new address[](1);
    _tokens[0] = address(wbnb);

    vm.prank(BOB);
    vm.expectRevert(ISmartTreasury.SmartTreasury_Unauthorized.selector);
    smartTreasury.distribute(_tokens);

    // Smart treasury after distributed must equal to before
    uint256 _WBNBTreasuryBalanceAfter = IERC20(address(wbnb)).balanceOf(address(smartTreasury));
    assertEq(_WBNBTreasuryBalanceAfter, _WBNBTreasuryBalanceBefore, "Smart treasury balance (WBNB)");
  }

  function testRevert_DistributeWithNonExistingRevenueToken_ShouldRevert() external {
    deal(address(cake), address(smartTreasury), 30 ether);
    uint256 _cakeTreasuryBalanceBefore = IERC20(address(cake)).balanceOf(address(smartTreasury));

    address[] memory _tokens = new address[](1);
    _tokens[0] = address(cake);

    vm.prank(ALICE);
    vm.expectRevert(ISmartTreasury.SmartTreasury_PathConfigNotFound.selector);
    smartTreasury.distribute(_tokens);

    // Smart treasury after distributed must equal to before
    uint256 _cakeTreasuryBalanceAfter = IERC20(address(cake)).balanceOf(address(smartTreasury));
    assertEq(_cakeTreasuryBalanceAfter, _cakeTreasuryBalanceBefore, "Smart treasury balance (Cake)");
  }

  function testCorrectness_DistributeFailedFromSwap_ShouldNotDistribute() external {
    // top up wbnb to smart treasury
    deal(address(wbnb), address(smartTreasury), 30 ether);
    uint256 _WBNBTreasuryBalanceBefore = IERC20(address(wbnb)).balanceOf(address(smartTreasury));

    // state before distribute
    uint256 _USDTrevenueBalanceBefore = IERC20(address(usdt)).balanceOf(REVENUE_TREASURY);
    uint256 _WBNBdevBalanceBefore = IERC20(address(wbnb)).balanceOf(DEV_TREASURY);
    uint256 _WBNBburnBalanceBefore = IERC20(address(wbnb)).balanceOf(BURN_TREASURY);

    // mock swap failed
    vm.mockCallRevert(
      address(routerV3),
      abi.encodeWithSelector(IPancakeSwapRouterV3.exactInput.selector),
      abi.encode("Failed swap")
    );

    address[] memory _tokens = new address[](1);
    _tokens[0] = address(wbnb);
    vm.prank(ALICE);
    smartTreasury.distribute(_tokens);

    // state after distribute
    uint256 _revenueBalanceAfter = IERC20(address(usdt)).balanceOf(REVENUE_TREASURY);
    uint256 _devBalanceAfter = IERC20(address(wbnb)).balanceOf(DEV_TREASURY);
    uint256 _burnBalanceAfter = IERC20(address(wbnb)).balanceOf(BURN_TREASURY);

    // after should be equal to before
    assertEq(_revenueBalanceAfter, _USDTrevenueBalanceBefore, "Revenue Treasury Balance (USDT)");
    assertEq(_devBalanceAfter, _WBNBdevBalanceBefore, "Dev Treasury Balance (WBNB)");
    assertEq(_burnBalanceAfter, _WBNBburnBalanceBefore, "Burn Treasury Balance (WBNB)");

    // Smart treasury after must equal to before
    uint256 _WBNBTreasuryBalanceAfter = IERC20(address(wbnb)).balanceOf(address(smartTreasury));
    assertEq(_WBNBTreasuryBalanceAfter, _WBNBTreasuryBalanceBefore, "Smart treasury balance (WBNB)");
  }

  function testCorrectness_WhenSwapFailedOtherDistribution_ShoulWork() external {
    // top up 2 tokens ot treasury
    // wbnb (failed)
    // eth (passed)
    deal(address(wbnb), address(smartTreasury), normalizeEther(3 ether, wbnb.decimals()));
    deal(address(eth), address(smartTreasury), normalizeEther(3 ether, eth.decimals()));

    uint256 _wbnbTreasuryBefore = IERC20(wbnb).balanceOf(address(smartTreasury));

    // mock fail for wbnb by slippage
    vm.mockCall(
      address(oracleMedianizer),
      abi.encodeWithSelector(IPriceOracle.getPrice.selector, address(wbnb), usd),
      abi.encode(normalizeEther(500 ether, wbnb.decimals()), 0)
    );

    address[] memory _tokens = new address[](2);
    _tokens[0] = address(wbnb);
    _tokens[1] = address(eth);
    vm.prank(ALICE);
    smartTreasury.distribute(_tokens);

    uint256 _wbnbTreasuryAfter = IERC20(wbnb).balanceOf(address(smartTreasury));
    uint256 _ethTreasuryAfter = IERC20(eth).balanceOf(address(smartTreasury));

    // smart treasury (wbnb) before must equal to after
    assertEq(_wbnbTreasuryAfter, _wbnbTreasuryBefore, "WBNB smart treasury");
    // smart treasury (eth) must have nothing
    assertEq(_ethTreasuryAfter, 0, "ETH smart treasury");
  }

  function testRevert_WhenOracleGetPriceFailed_ShouldRevert() external {
    // set path for cake to usdt
    bytes[] memory _paths = new bytes[](1);
    _paths[0] = abi.encodePacked(address(cake), uint24(2500), address(usdt));
    pathReaderV3.setPaths(_paths);

    deal(address(cake), address(smartTreasury), 30 ether);

    // call distribute
    address[] memory _tokens = new address[](1);
    _tokens[0] = address(cake);
    vm.prank(ALICE);
    vm.expectRevert("OracleMedianizer::getPrice:: no primary source");
    smartTreasury.distribute(_tokens);
  }

  function testCorrectness_DecimalDiff_ShouldWork() external {
    // tokenIn: doge (8 decimals)
    // tokenOut (revenue token): wbnb (18 decimals)

    // set revenue token
    vm.prank(DEPLOYER);
    smartTreasury.setRevenueToken(address(wbnb));

    uint256 _distributeAmount = normalizeEther(3 ether, doge.decimals());

    bytes[] memory _paths = new bytes[](1);
    _paths[0] = abi.encodePacked(address(doge), uint24(2500), address(wbnb));
    pathReaderV3.setPaths(_paths);

    // mock price doge on oracle doge = 0.0715291 * 1e18
    vm.mockCall(
      address(oracleMedianizer),
      abi.encodeWithSelector(IPriceOracle.getPrice.selector, address(doge), usd),
      abi.encode(0.0715291 ether, 0)
    );

    // expect amount out
    (uint256 _expectedAmountOut, , , ) = quoterV2.quoteExactInput(
      abi.encodePacked(address(doge), uint24(2500), address(wbnb)),
      normalizeEther(1 ether, doge.decimals())
    );

    // top up doge to smart treasury
    deal(address(doge), address(smartTreasury), _distributeAmount);

    address[] memory _tokens = new address[](1);
    _tokens[0] = address(doge);
    vm.prank(ALICE);
    smartTreasury.distribute(_tokens);

    uint256 _WBNBrevenueTreasury = IERC20(address(wbnb)).balanceOf(REVENUE_TREASURY);
    assertCloseBps(_WBNBrevenueTreasury, _expectedAmountOut, 100);

    // expect distributed amount = 1 doge on dev treasury
    uint256 _DogeDevTreasuryBalance = IERC20(address(doge)).balanceOf(DEV_TREASURY);
    assertCloseBps(_DogeDevTreasuryBalance, normalizeEther(1 ether, doge.decimals()), 100);

    // expect distributed amount = 1 doge on burn treasury
    uint256 _burnDogeTreasury = IERC20(address(doge)).balanceOf(BURN_TREASURY);
    assertCloseBps(_burnDogeTreasury, normalizeEther(1 ether, doge.decimals()), 100);
  }

  function testCorrectness_DistributeTokenIsRevenueToken_ShouldWork() external {
    // state before distribute
    uint256 _revenueBalanceBefore = IERC20(address(usdt)).balanceOf(REVENUE_TREASURY);
    uint256 _devBalanceBefore = IERC20(address(usdt)).balanceOf(DEV_TREASURY);
    uint256 _burnBalanceBefore = IERC20(address(usdt)).balanceOf(BURN_TREASURY);

    // top up usdt to balance smart treasury
    deal(address(usdt), address(smartTreasury), normalizeEther(30 ether, usdt.decimals()));

    address[] memory _tokens = new address[](1);
    _tokens[0] = address(usdt);
    vm.prank(ALICE);
    smartTreasury.distribute(_tokens);

    // state after distribute
    uint256 _revenueBalanceAfter = IERC20(address(usdt)).balanceOf(REVENUE_TREASURY);
    uint256 _devBalanceAfter = IERC20(address(usdt)).balanceOf(DEV_TREASURY);
    uint256 _burnBalanceAfter = IERC20(address(usdt)).balanceOf(BURN_TREASURY);

    uint256 _expectAmount = normalizeEther(10 ether, usdt.decimals());

    // rev treasury (get usdt)
    assertCloseBps(_revenueBalanceAfter, _revenueBalanceBefore + _expectAmount, 100);
    // dev treasury (get usdt)
    assertCloseBps(_devBalanceAfter, _devBalanceBefore + _expectAmount, 100);
    // burn treasury (get usdt)
    assertCloseBps(_burnBalanceAfter, _burnBalanceBefore + _expectAmount, 100);

    // Smart treasury after distribute must have nothing
    uint256 _USDTTreasuryBalanceAfter = IERC20(address(usdt)).balanceOf(address(smartTreasury));
    assertEq(_USDTTreasuryBalanceAfter, 0, "Smart treasury balance (USDT)");
  }

  function testCorrectness_TooSmallSlippage_ShouldWork() external {
    // state before distribute
    uint256 _revenueBalanceBefore = IERC20(address(usdt)).balanceOf(REVENUE_TREASURY);
    uint256 _devBalanceBefore = IERC20(address(wbnb)).balanceOf(DEV_TREASURY);
    uint256 _burnBalanceBefore = IERC20(address(wbnb)).balanceOf(BURN_TREASURY);

    // top up bnb to smart treasury
    deal(address(wbnb), address(smartTreasury), 30 ether);

    // mock oracle under rate
    vm.mockCall(
      address(oracleMedianizer),
      abi.encodeWithSelector(IPriceOracle.getPrice.selector, address(wbnb), usd),
      abi.encode(normalizeEther(100 ether, wbnb.decimals()), 0)
    );

    address[] memory _tokens = new address[](1);
    _tokens[0] = address(wbnb);
    vm.prank(ALICE);
    smartTreasury.distribute(_tokens);

    // expect amount
    (uint256 _expectedAmountOut, , , ) = quoterV2.quoteExactInput(
      abi.encodePacked(address(wbnb), uint24(500), address(usdt)),
      10 ether
    );

    // state after distribute
    uint256 _revenueBalanceAfter = IERC20(address(usdt)).balanceOf(REVENUE_TREASURY);
    uint256 _devBalanceAfter = IERC20(address(wbnb)).balanceOf(DEV_TREASURY);
    uint256 _burnBalanceAfter = IERC20(address(wbnb)).balanceOf(BURN_TREASURY);

    // rev treasury (get usdt)
    assertCloseBps(_revenueBalanceAfter, _revenueBalanceBefore + _expectedAmountOut, 100);
    // dev treasury (get wbnb)
    assertCloseBps(_devBalanceAfter, _devBalanceBefore + 10 ether, 100);

    // burn treasury (get wbnb)
    assertCloseBps(_burnBalanceAfter, _burnBalanceBefore + 10 ether, 100);

    // Smart treasury after must equal to before
    uint256 _WBNBTreasuryBalanceAfter = IERC20(address(wbnb)).balanceOf(address(smartTreasury));
    assertEq(_WBNBTreasuryBalanceAfter, 0, "Smart treasury balance (WBNB)");
  }

  function testCorrectness_TooMuchSlippage_ShouldSkip() external {
    // top up bnb to smart treasury
    deal(address(wbnb), address(smartTreasury), 30 ether);
    uint256 _WBNBTreasuryBalanceBefore = IERC20(address(wbnb)).balanceOf(address(smartTreasury));

    // mock oracle under rate
    vm.mockCall(
      address(oracleMedianizer),
      abi.encodeWithSelector(IPriceOracle.getPrice.selector, address(wbnb), usd),
      abi.encode(normalizeEther(500 ether, wbnb.decimals()), 0)
    );

    address[] memory _tokens = new address[](1);
    _tokens[0] = address(wbnb);
    vm.prank(ALICE);
    smartTreasury.distribute(_tokens);

    // Smart treasury after must equal to before
    uint256 _WBNBTreasuryBalanceAfter = IERC20(address(wbnb)).balanceOf(address(smartTreasury));
    assertEq(_WBNBTreasuryBalanceAfter, _WBNBTreasuryBalanceBefore, "Smart treasury balance (WBNB)");
  }

  function testCorrectness_WhenV3NoLiquidity_V2Liquidity_ShouldSupport() external {
    // set path v2
    address[] memory _pathV2 = new address[](2);
    _pathV2[0] = address(wbnb);
    _pathV2[1] = address(usdt);
    IUniSwapV2PathReader.PathParams[] memory _pathV2Param = new IUniSwapV2PathReader.PathParams[](1);
    _pathV2Param[0] = IUniSwapV2PathReader.PathParams(address(routerV2), _pathV2);
    pathReaderV2.setPaths(_pathV2Param);

    // top up wbnb to smart treasury
    deal(address(wbnb), address(smartTreasury), 30 ether);

    // mock call that v3 path not exists
    vm.mockCall(
      address(pathReaderV3),
      abi.encodeWithSelector(IUniSwapV3PathReader.paths.selector, address(wbnb), address(usdt)),
      abi.encode(0)
    );

    // expect amount out
    uint256[] memory _expectedAmount = routerV2.getAmountsOut(
      10 ether,
      pathReaderV2.getPath(address(wbnb), address(usdt)).path
    );

    address[] memory _tokens = new address[](1);
    _tokens[0] = address(wbnb);

    // distribute
    vm.prank(ALICE);
    smartTreasury.distribute(_tokens);

    assertEq(wbnb.balanceOf(address(smartTreasury)), 0, "WBNB Smart Treasury");
    assertCloseBps(usdt.balanceOf(REVENUE_TREASURY), _expectedAmount[1], 100);
    assertCloseBps(wbnb.balanceOf(DEV_TREASURY), 10 ether, 100);
    assertCloseBps(wbnb.balanceOf(BURN_TREASURY), 10 ether, 100);
  }
}
