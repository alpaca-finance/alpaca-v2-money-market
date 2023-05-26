// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import { DSTest } from "solidity/tests/base/DSTest.sol";
import "../utils/Components.sol";

// interfaces
import { IERC20 } from "solidity/contracts/money-market/interfaces/IERC20.sol";
import { IUniSwapV2PathReader } from "solidity/contracts/reader/interfaces/IUniSwapV2PathReader.sol";

// implementation
import { UniSwapV2LikePathReader } from "solidity/contracts/reader/UniSwapV2LikePathReader.sol";
import { MockERC20 } from "solidity/tests/mocks/MockERC20.sol";

contract UniSwapV2LikePathReaderTest is DSTest, StdUtils, StdAssertions, StdCheats {
  using stdStorage for StdStorage;

  VM internal constant vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

  address DEPLOYER = makeAddr("DEPLOYER");

  address pcsRouterV2 = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

  IERC20 public constant btcb = IERC20(0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c);
  IERC20 public constant eth = IERC20(0x2170Ed0880ac9A755fd29B2688956BD959F933F8);
  IERC20 public constant wbnb = IERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
  IERC20 public constant usdt = IERC20(0x55d398326f99059fF775485246999027B3197955);
  IERC20 public constant usdc = IERC20(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d);
  IERC20 public constant cake = IERC20(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
  IERC20 public constant doge = IERC20(0xbA2aE424d960c26247Dd6c32edC70B295c744C43);

  IUniSwapV2PathReader pathReaderV2;

  function setUp() public {
    vm.createSelectFork("bsc_mainnet", 28_113_725);

    vm.prank(DEPLOYER);
    pathReaderV2 = new UniSwapV2LikePathReader();
  }

  function testRevert_UnauthorizedSetPath_ShouldRevert() external {
    address _token0 = address(btcb);
    address _token1 = address(wbnb);

    address[] memory _path = new address[](2);
    _path[0] = _token0;
    _path[1] = _token1;

    IUniSwapV2PathReader.PathParams[] memory _params = new IUniSwapV2PathReader.PathParams[](1);
    _params[0] = IUniSwapV2PathReader.PathParams({ router: pcsRouterV2, path: _path });

    vm.expectRevert("Ownable: caller is not the owner");
    pathReaderV2.setPaths(_params);
  }

  function testCorrectness_SetPath_ShouldWork() external {
    address _token0 = address(btcb);
    address _token1 = address(wbnb);

    address[] memory _path = new address[](2);
    _path[0] = _token0;
    _path[1] = _token1;

    IUniSwapV2PathReader.PathParams[] memory _params = new IUniSwapV2PathReader.PathParams[](1);
    _params[0] = IUniSwapV2PathReader.PathParams({ router: pcsRouterV2, path: _path });

    vm.prank(DEPLOYER);
    pathReaderV2.setPaths(_params);

    assertEq(pathReaderV2.getPath(_token0, _token1).router, pcsRouterV2);
    assertEq(pathReaderV2.getPath(_token0, _token1).path, _path);
  }

  function testRevert_SetInvalidTokenPath_ShouldRevert() external {
    address _token0 = address(new MockERC20("token0", "TK0", 18));
    address _token1 = address(wbnb);

    address[] memory _path = new address[](2);
    _path[0] = _token0;
    _path[1] = _token1;

    IUniSwapV2PathReader.PathParams[] memory _params = new IUniSwapV2PathReader.PathParams[](1);
    _params[0] = IUniSwapV2PathReader.PathParams({ router: pcsRouterV2, path: _path });

    vm.prank(DEPLOYER);
    // it will revert at getAmountsIn, due to the pool is not existing
    vm.expectRevert();
    pathReaderV2.setPaths(_params);
  }

  function testRevert_SetLongTokenPath_ShouldRevert() external {
    address[] memory _path = new address[](6);
    IUniSwapV2PathReader.PathParams[] memory _params = new IUniSwapV2PathReader.PathParams[](1);
    _params[0] = IUniSwapV2PathReader.PathParams({ router: pcsRouterV2, path: _path });

    vm.prank(DEPLOYER);
    vm.expectRevert();
    pathReaderV2.setPaths(_params);
  }
}
