// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseFork } from "./BaseFork.sol";
import { ISmartTreasury } from "solidity/contracts/smart-treasury/ISmartTreasury.sol";
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
    smartTreasury.setAllocs(100, 100, 100);
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
  }

  function testRevert_UnauthorizedCallDistribute_ShouldRevert() external {
    deal(address(wbnb), address(smartTreasury), 30 ether);

    address[] memory _tokens = new address[](1);
    _tokens[0] = address(wbnb);

    vm.prank(BOB);
    vm.expectRevert(ISmartTreasury.SmartTreasury_Unauthorized.selector);
    smartTreasury.distribute(_tokens);
  }

  function testRevert_DistributeWithNonExistingRevenueToken_ShouldRevert() external {
    deal(address(wbnb), address(smartTreasury), 30 ether);

    address[] memory _tokens = new address[](1);
    _tokens[0] = address(cake);

    vm.prank(ALICE);
    vm.expectRevert(ISmartTreasury.SmartTreasury_PathConfigNotFound.selector);
    smartTreasury.distribute(_tokens);
  }

  function testCorrectness_DistributeFailedFromSwap_ShouldNotDistribute() external {
    // state before distribute
    uint256 _revenueBalanceBefore = IERC20(address(usdt)).balanceOf(REVENUE_TREASURY);
    uint256 _devBalanceBefore = IERC20(address(wbnb)).balanceOf(DEV_TREASURY);
    uint256 _burnBalanceBefore = IERC20(address(wbnb)).balanceOf(BURN_TREASURY);

    // top up balance smart treasury
    // top up wbnb
    deal(address(wbnb), address(smartTreasury), 30 ether);

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
  }
}
