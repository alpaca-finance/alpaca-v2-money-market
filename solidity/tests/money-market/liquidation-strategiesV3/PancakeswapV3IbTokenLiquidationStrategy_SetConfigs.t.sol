// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BasePCSV3LiquidationForkTest } from "./BasePCSV3LiquidationForkTest.sol";
import { PancakeswapV3IbTokenLiquidationStrategy } from "../../../contracts/money-market/PancakeswapV3IbTokenLiquidationStrategy.sol";

// libs
import { LibPCSV3PoolAddress } from "../../libs/LibPCSV3PoolAddress.sol";

// interfaces
import { IPancakeV3PoolState } from "../../../contracts/money-market/interfaces/IPancakeV3Pool.sol";

// mocks
import { MockERC20 } from "solidity/tests/mocks/MockERC20.sol";

contract PancakeswapV3IbTokenLiquidationStrategy_SetConfigs is BasePCSV3LiquidationForkTest {
  PancakeswapV3IbTokenLiquidationStrategy internal liquidationStrat;

  function setUp() public override {
    super.setUp();
    liquidationStrat = new PancakeswapV3IbTokenLiquidationStrategy(address(router), address(moneyMarket));
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

  function testRevert_WhenOwnerSetNonExistingPath_ShouldRevert() external {
    // random token
    MockERC20 _randomToken0 = new MockERC20("Random0", "RD0", 18);
    MockERC20 _randomToken1 = new MockERC20("Random1", "RD1", 18);

    bytes[] memory _paths = new bytes[](1);
    _paths[0] = abi.encodePacked(address(_randomToken0), poolFee, address(_randomToken1));

    // Expect EVM Error. Since we call pool.liquidity() where pool is not existing
    vm.expectRevert();
    liquidationStrat.setPaths(_paths);

    // expect pool address
    address _poolAddress = LibPCSV3PoolAddress.computeAddress(
      PANCAKE_V3_POOL_DEPLOYER,
      LibPCSV3PoolAddress.getPoolKey(address(_randomToken0), address(_randomToken1), poolFee)
    );

    // when mock liquidity => 0, should revert PancakeswapV3IbTokenLiquidationStrategy_NoLiquidity correctly
    vm.mockCall(address(_poolAddress), abi.encodeWithSelector(IPancakeV3PoolState.liquidity.selector), abi.encode(0));
    vm.expectRevert(
      abi.encodeWithSelector(
        PancakeswapV3IbTokenLiquidationStrategy.PancakeswapV3IbTokenLiquidationStrategy_NoLiquidity.selector,
        [address(_randomToken0), address(_randomToken1), address(uint160(poolFee))]
      )
    );
    liquidationStrat.setPaths(_paths);
  }

  function testRevert_WhenCallerIsNotOwner_ShouldRevert() external {
    bytes[] memory _paths = new bytes[](1);
    _paths[0] = abi.encodePacked(address(wbnb), poolFee, address(cake));

    vm.prank(ALICE);
    vm.expectRevert("Ownable: caller is not the owner");
    liquidationStrat.setPaths(_paths);
  }
}
