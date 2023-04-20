// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BasePCSV3IbLiquidationForkTest } from "./BasePCSV3IbLiquidationForkTest.sol";
import { PancakeswapV3IbTokenLiquidationStrategy } from "../../../contracts/money-market/PancakeswapV3IbTokenLiquidationStrategy.sol";

// mocks
import { MockERC20 } from "solidity/tests/mocks/MockERC20.sol";
import { MockMoneyMarket } from "../../mocks/MockMoneyMarket.sol";
import { MockMoneyMarketV3 } from "../../mocks/MockMoneyMarketV3.sol";

contract PancakeswapV3IbTokenLiquidationStrategy_SetConfigs is BasePCSV3IbLiquidationForkTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenOwnerSetCallersOk_ShouldWork() external {
    address[] memory _callers = new address[](1);
    _callers[0] = BOB;

    liquidationStrat.setCallersOk(_callers, true);

    assertTrue(liquidationStrat.callersOk(BOB));
  }

  function testRevert_WhenNonOwnerSetCallersOk_ShouldRevert() external {
    address[] memory _callers = new address[](1);
    _callers[0] = BOB;

    vm.prank(BOB);
    vm.expectRevert("Ownable: caller is not the owner");
    liquidationStrat.setCallersOk(_callers, true);
  }

  function testCorrectness_WhenOwnerSetPathSingleHop_ShouldWork() external {
    // bytes[] paths
    bytes[] memory _paths = new bytes[](1);
    _paths[0] = abi.encodePacked(address(cake), poolFee, address(wbnb));

    liquidationStrat.setPaths(_paths);
    assertEq(liquidationStrat.paths(address(cake), address(wbnb)), _paths[0]);
  }

  function testCorrectness_WhenOwnerSetPathMultiHop_ShouldWork() external {
    bytes[] memory _paths = new bytes[](1);
    _paths[0] = abi.encodePacked(address(cake), poolFee, address(usdt), poolFee, address(wbnb));
    liquidationStrat.setPaths(_paths);

    assertEq(liquidationStrat.paths(address(cake), address(wbnb)), _paths[0]);
  }

  function testRevert_WhenOwnerSetRandomPath() external {
    // random token
    MockERC20 _randomToken0 = new MockERC20("Random0", "RD0", 18);
    MockERC20 _randomToken1 = new MockERC20("Random1", "RD1", 18);

    bytes[] memory _paths = new bytes[](1);
    _paths[0] = abi.encodePacked(address(_randomToken0), poolFee, address(_randomToken1));

    // TODO: Revert with?
    vm.expectRevert();
    liquidationStrat.setPaths(_paths);
  }

  function testRevert_WhenNonOwnerSetPaths() external {
    bytes[] memory _paths = new bytes[](1);
    _paths[0] = abi.encodePacked(address(wbnb), poolFee, address(cake));

    vm.prank(ALICE);
    vm.expectRevert("Ownable: caller is not the owner");
    liquidationStrat.setPaths(_paths);
  }
}
