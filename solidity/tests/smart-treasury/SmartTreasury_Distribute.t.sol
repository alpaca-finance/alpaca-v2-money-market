// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseFork } from "./BaseFork.sol";
import { ISmartTreasury } from "solidity/contracts/interfaces/ISmartTreasury.sol";
import { IPancakeSwapRouterV3 } from "solidity/contracts/money-market/interfaces/IPancakeSwapRouterV3.sol";
import { IERC20 } from "solidity/contracts/money-market/interfaces/IERC20.sol";

contract SmartTreasury_Distribute is BaseFork {
  function setUp() public override {
    super.setUp();

    // setup whitelisted caller
    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;
    vm.prank(DEPLOYER);
    smartTreasury.setWhitelistedCallers(_callers, true);

    vm.startPrank(ALICE);
    // setup revenue token, alloc points and treasury address
    smartTreasury.setRevenueToken(address(usdt));
    smartTreasury.setAllocPoints(100, 100, 100);
    smartTreasury.setTreasuryAddresses(REVENUE_TREASURY, DEV_TREASURY, BURN_TREASURY);
    vm.stopPrank();
  }

  function testCorrectness_CallDistribute_ShouldWork() external {
    // state before distribute
    uint256 _revenueBalanceBefore = IERC20(address(usdt)).balanceOf(REVENUE_TREASURY);
    uint256 _devBalanceBefore = IERC20(address(wbnb)).balanceOf(DEV_TREASURY);
    uint256 _burnBalanceBefore = IERC20(address(wbnb)).balanceOf(BURN_TREASURY);

    // top up balance smart treasury
    // top up wbnb
    deal(address(wbnb), address(smartTreasury), 30 ether);

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
    // tolerance ~5%
    assertCloseBps(_revenueBalanceAfter, _revenueBalanceBefore + _expectedAmountOut, 500);
    // dev treasury (get wbnb)
    assertEq(_devBalanceAfter, _devBalanceBefore + 10 ether, "Dev Treasury Balance (WBNB)");

    // burn treasury (get wbnb)
    assertEq(_burnBalanceAfter, _burnBalanceBefore + 10 ether, "Burn Treasury Balance (WBNB)");

    // Smart treasury after must equal to before
    uint256 _WBNBTreasuryBalanceAfter = IERC20(address(wbnb)).balanceOf(address(smartTreasury));
    assertEq(_WBNBTreasuryBalanceAfter, 0, "Smart treasury balance (WBNB)");
  }

  function testRevert_UnauthorizedCallDistribute_ShouldRevert() external {
    deal(address(wbnb), address(smartTreasury), 30 ether);
    uint256 _WBNBTreasuryBalanceBefore = IERC20(address(wbnb)).balanceOf(address(smartTreasury));

    address[] memory _tokens = new address[](1);
    _tokens[0] = address(wbnb);

    vm.prank(BOB);
    vm.expectRevert(ISmartTreasury.SmartTreasury_Unauthorized.selector);
    smartTreasury.distribute(_tokens);

    // Smart treasury must have nothing left
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

    // Smart treasury after must equal to before
    uint256 _cakeTreasuryBalanceAfter = IERC20(address(cake)).balanceOf(address(smartTreasury));
    assertEq(_cakeTreasuryBalanceAfter, _cakeTreasuryBalanceBefore, "Smart treasury balance (Cake)");
  }

  function testCorrectness_DistributeFailedFromSwap_ShouldNotDistribute() external {
    // top up balance smart treasury
    // top up wbnb
    deal(address(wbnb), address(smartTreasury), 30 ether);
    uint256 _WBNBTreasuryBalanceBefore = IERC20(address(wbnb)).balanceOf(address(smartTreasury));

    // state before distribute
    uint256 _revenueBalanceBefore = IERC20(address(usdt)).balanceOf(REVENUE_TREASURY);
    uint256 _devBalanceBefore = IERC20(address(wbnb)).balanceOf(DEV_TREASURY);
    uint256 _burnBalanceBefore = IERC20(address(wbnb)).balanceOf(BURN_TREASURY);

    vm.mockCallRevert(
      address(router),
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
    assertEq(_revenueBalanceAfter, _revenueBalanceBefore, "Revenue Treasury Balance (USDT)");
    assertEq(_devBalanceAfter, _devBalanceBefore, "Dev Treasury Balance (WBNB)");
    assertEq(_burnBalanceAfter, _burnBalanceBefore, "Burn Treasury Balance (WBNB)");

    // Smart treasury after must equal to before
    uint256 _WBNBTreasuryBalanceAfter = IERC20(address(wbnb)).balanceOf(address(smartTreasury));
    assertEq(_WBNBTreasuryBalanceAfter, _WBNBTreasuryBalanceBefore, "Smart treasury balance (WBNB)");
  }

  struct CacheState {
    uint256 _rev;
    uint256 _dev;
    uint256 _burn;
  }

  function testCorrectness_WhenSwapFailedOtherDistribution_ShoulWork() external {
    // set path for cake to usdt
    bytes[] memory _paths = new bytes[](1);
    _paths[0] = abi.encodePacked(address(cake), uint24(2500), address(usdt));
    pathReader.setPaths(_paths);

    // top up 2 tokens
    // wbnb
    // cake
    deal(address(wbnb), address(smartTreasury), 30 ether);
    deal(address(cake), address(smartTreasury), 30 ether);

    uint256 _WBNBTreasuryBalanceBefore = IERC20(address(wbnb)).balanceOf(address(smartTreasury));

    CacheState memory _stateWBNBBefore = CacheState(
      IERC20(address(usdt)).balanceOf(REVENUE_TREASURY),
      IERC20(address(wbnb)).balanceOf(DEV_TREASURY),
      IERC20(address(wbnb)).balanceOf(BURN_TREASURY)
    );

    CacheState memory _stateCakeBefore = CacheState(
      IERC20(address(usdt)).balanceOf(REVENUE_TREASURY),
      IERC20(address(cake)).balanceOf(DEV_TREASURY),
      IERC20(address(cake)).balanceOf(BURN_TREASURY)
    );

    // mock fail for wbnb
    // *cake must work normally
    IPancakeSwapRouterV3.ExactInputParams memory _params = IPancakeSwapRouterV3.ExactInputParams({
      path: abi.encodePacked(address(wbnb), uint24(500), address(usdt)),
      recipient: REVENUE_TREASURY,
      deadline: block.timestamp,
      amountIn: 10 ether,
      amountOutMinimum: 0
    });

    vm.mockCallRevert(
      address(router),
      abi.encodeWithSelector(IPancakeSwapRouterV3.exactInput.selector, _params),
      abi.encode("WBNB to USDT Failed swap")
    );

    (uint256 _expectedAmountOut, , , ) = quoterV2.quoteExactInput(
      abi.encodePacked(address(cake), uint24(2500), address(usdt)),
      10 ether
    );

    // call distribute
    address[] memory _tokens = new address[](2);
    _tokens[0] = address(wbnb);
    _tokens[1] = address(cake);
    vm.prank(ALICE);
    smartTreasury.distribute(_tokens);

    // state after distribution
    CacheState memory _stateWBNBAfter = CacheState(
      IERC20(address(usdt)).balanceOf(REVENUE_TREASURY),
      IERC20(address(wbnb)).balanceOf(DEV_TREASURY),
      IERC20(address(wbnb)).balanceOf(BURN_TREASURY)
    );

    CacheState memory _stateCakeAfter = CacheState(
      IERC20(address(usdt)).balanceOf(REVENUE_TREASURY),
      IERC20(address(cake)).balanceOf(DEV_TREASURY),
      IERC20(address(cake)).balanceOf(BURN_TREASURY)
    );

    // 1. wbnb balance after must equal to balance before
    // Note: usdt balance = wbnb distribution (0) + cake distribution (expectAmountOut)
    // Then we have to deduct the increased amount from cake distribution
    assertCloseBps(_stateWBNBAfter._rev, _stateWBNBBefore._rev + _expectedAmountOut, 500);
    assertEq(_stateWBNBAfter._dev, _stateWBNBBefore._dev, "Dev treasury balance (WBNB)");
    assertEq(_stateWBNBAfter._burn, _stateWBNBBefore._burn, "Burn treasury balance (WBNB)");

    // 2. cake balanace after must work normally
    assertGt(_stateCakeAfter._rev, _stateCakeBefore._rev, "(CAKE) Revenue treasury balance (USDT)");
    assertEq(_stateCakeAfter._dev, _stateCakeBefore._dev + 10 ether, "Dev treasury balance (Cake)");
    assertEq(_stateCakeAfter._burn, _stateCakeBefore._burn + 10 ether, "Burn treasury balance (Cake)");

    // Smart Treasury balance test
    uint256 _WBNBTreasuryBalanceAfter = IERC20(address(wbnb)).balanceOf(address(smartTreasury));
    assertEq(_WBNBTreasuryBalanceAfter, _WBNBTreasuryBalanceBefore, "Smart treasury balance (WBNB)");
    uint256 _CakeTreasuryBalanceAfter = IERC20(address(cake)).balanceOf(address(smartTreasury));
    assertEq(_CakeTreasuryBalanceAfter, 0, "Smart treasury balance (Cake)");
  }
}
