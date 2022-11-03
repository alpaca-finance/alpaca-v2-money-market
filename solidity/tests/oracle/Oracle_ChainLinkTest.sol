// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BaseTest, console, MockERC20 } from "../base/BaseTest.sol";

import { ChainLinkPriceOracle } from "../../contracts/oracle/ChainLinkPriceOracle.sol";
import { IAggregatorV3 } from "../../contracts/oracle/interfaces/IAggregatorV3.sol";
import { MockChainLinkAggregator } from "../mocks/MockChainLinkAggregator.sol";

contract Oracle_ChainLinkPriceOracleTest is BaseTest {
  IAggregatorV3[] _fakeAggregatorWETHUSD;
  IAggregatorV3[] _fakeAggregatorUSDCUSD;
  IAggregatorV3[] _fakeAggregatorWETHUSDC;
  ChainLinkPriceOracle oracle;

  function setUp() public virtual {
    _fakeAggregatorWETHUSD = new IAggregatorV3[](1);
    _fakeAggregatorWETHUSD[0] = new MockChainLinkAggregator(1500e18, 18);

    _fakeAggregatorUSDCUSD = new IAggregatorV3[](1);
    _fakeAggregatorUSDCUSD[0] = new MockChainLinkAggregator(1e18, 18);

    _fakeAggregatorWETHUSDC = new IAggregatorV3[](2);
    _fakeAggregatorWETHUSDC[0] = new MockChainLinkAggregator(1500e18, 18);
    _fakeAggregatorWETHUSDC[1] = new MockChainLinkAggregator(1e18, 18);

    oracle = new ChainLinkPriceOracle();
    oracle.initialize();
    address oldOwner = oracle.owner();
    vm.prank(oldOwner);
    oracle.transferOwnership(DEPLOYER);
  }

  function testCorrectness_NotOwner_setPriceFeed_shouldRevertCallerIsNotOwner() external {
    address[] memory t0 = new address[](1);
    t0[0] = address(weth);

    address[] memory t1 = new address[](1);
    t1[0] = address(usd);

    IAggregatorV3[][] memory sources = new IAggregatorV3[][](1);
    sources[0] = _fakeAggregatorWETHUSD;

    vm.startPrank(ALICE);
    try oracle.setPriceFeeds(t0, t1, sources) {
      fail();
    } catch Error(string memory reason) {
      assertEq(reason, "Ownable: caller is not the owner", "upgrade not owner");
    }
    vm.stopPrank();
  }

  function testCorrectness_setPriceFeed_shouldPass() external {
    address[] memory t0 = new address[](2);
    t0[0] = address(weth);
    t0[1] = address(usdc);

    address[] memory t1 = new address[](2);
    t1[0] = address(usd);
    t1[1] = address(usd);

    IAggregatorV3[][] memory sources = new IAggregatorV3[][](2);

    sources[0] = _fakeAggregatorWETHUSD;
    sources[1] = _fakeAggregatorUSDCUSD;

    vm.prank(DEPLOYER);
    oracle.setPriceFeeds(t0, t1, sources);

    uint256 wethCount = oracle.priceFeedCount(address(weth), address(usd));
    uint256 usdcCount = oracle.priceFeedCount(address(usdc), address(usd));
    assertEq(wethCount, 1);
    assertEq(usdcCount, 1);
  }

  function testCorrectness_getPriceBeforeSet_shouldRevertNoSource() external {
    address[] memory t0 = new address[](1);
    t0[0] = address(weth);

    address[] memory t1 = new address[](1);
    t1[0] = address(usdc);

    IAggregatorV3[][] memory sources = new IAggregatorV3[][](1);
    sources[0] = _fakeAggregatorWETHUSD;

    vm.prank(DEPLOYER);
    oracle.setPriceFeeds(t0, t1, sources);

    vm.expectRevert(ChainLinkPriceOracle.ChainlinkPriceOracle_NoSource.selector);
    oracle.getPrice(address(weth), address(usd));
  }

  function testCorrectness_getPrice_shouldPass() external {
    address[] memory t0 = new address[](3);
    t0[0] = address(weth);
    t0[1] = address(usdc);
    t0[2] = address(weth);

    address[] memory t1 = new address[](3);
    t1[0] = address(usd);
    t1[1] = address(usd);
    t1[2] = address(usdc);

    IAggregatorV3[][] memory sources = new IAggregatorV3[][](3);
    sources[0] = _fakeAggregatorWETHUSD;
    sources[1] = _fakeAggregatorUSDCUSD;
    sources[2] = _fakeAggregatorWETHUSDC;

    vm.prank(DEPLOYER);
    oracle.setPriceFeeds(t0, t1, sources);
    (uint256 wethPrice, ) = oracle.getPrice(address(weth), address(usd));
    assertEq(wethPrice, 1500 ether);

    (uint256 usdcPrice, ) = oracle.getPrice(address(usdc), address(usd));
    assertEq(usdcPrice, 1 ether);

    (uint256 wethUsdcPrice, ) = oracle.getPrice(address(weth), address(usdc));
    assertEq(wethUsdcPrice, 1500 ether);
  }
}
