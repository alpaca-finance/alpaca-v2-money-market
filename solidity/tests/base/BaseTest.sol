// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { DSTest } from "./DSTest.sol";

import { VM } from "../utils/VM.sol";
import { console } from "../utils/console.sol";

// oracle
import { SimplePriceOracle } from "../../contracts/oracle/SimplePriceOracle.sol";
import { ChainLinkPriceOracle2, IPriceOracle } from "../../contracts/oracle/ChainLinkPriceOracle2.sol";

// Mocks
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockWNative } from "../mocks/MockWNative.sol";
import { MockWNativeRelayer } from "../mocks/MockWNativeRelayer.sol";
import { MockChainLinkPriceOracle } from "../mocks/MockChainLinkPriceOracle.sol";

import { console } from "../utils/console.sol";

contract BaseTest is DSTest {
  uint256 internal constant subAccount0 = 0;
  uint256 internal constant subAccount1 = 1;

  address internal constant DEPLOYER = address(0x01);
  address internal constant ALICE = address(0x88);
  address internal constant BOB = address(0x168);
  address internal constant CAT = address(0x99);
  address internal constant EVE = address(0x55);

  VM internal constant vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

  MockWNative internal nativeToken;
  MockERC20 internal weth;
  MockERC20 internal usdc;
  MockERC20 internal btc;
  MockERC20 internal opm; // open market token
  address internal usd;
  MockERC20 internal isolateToken;

  MockERC20 internal ibWeth;
  MockERC20 internal ibBtc;
  MockERC20 internal ibUsdc;
  MockERC20 internal ibIsolateToken;
  MockERC20 internal ibWNative;

  IPriceOracle internal oracle;

  MockWNativeRelayer nativeRelayer;

  constructor() {
    weth = deployMockErc20("Wrapped Ethereum", "WETH", 18);
    btc = deployMockErc20("Bitcoin", "BTC", 18);
    usdc = deployMockErc20("USD COIN", "USDC", 18);
    usd = address(0x115dffFFfffffffffFFFffffFFffFfFfFFFFfFff);
    opm = deployMockErc20("OPM Token", "OPM", 9);
    isolateToken = deployMockErc20("ISOLATETOKEN", "ISOLATETOKEN", 18);
    nativeToken = deployMockWNative();

    ibWeth = deployMockErc20("Inerest Bearing Wrapped Ethereum", "IBWETH", 18);
    ibBtc = deployMockErc20("Inerest Bearing Bitcoin", "IBBTC", 18);
    ibUsdc = deployMockErc20("Inerest USD COIN", "IBUSDC", 18);
    ibIsolateToken = deployMockErc20("IBISOLATETOKEN", "IBISOLATETOKEN", 18);
    ibWNative = deployMockErc20("Interest Bearing WNATIVE", "WNATIVE", 18);

    nativeRelayer = deployMockWNativeRelayer();

    vm.deal(ALICE, 1000 ether);

    weth.mint(ALICE, 1000 ether);
    btc.mint(ALICE, 1000 ether);
    usdc.mint(ALICE, 1000 ether);
    opm.mint(ALICE, 1000 ether);
    isolateToken.mint(ALICE, 1000 ether);

    weth.mint(EVE, 1000 ether);
    btc.mint(EVE, 1000 ether);
    usdc.mint(EVE, 1000 ether);
    opm.mint(EVE, 1000 ether);
    isolateToken.mint(EVE, 1000 ether);

    weth.mint(BOB, 1000 ether);
    btc.mint(BOB, 1000 ether);
    usdc.mint(BOB, 1000 ether);
    isolateToken.mint(BOB, 1000 ether);
  }

  function deployMockErc20(
    string memory name,
    string memory symbol,
    uint8 decimals
  ) internal returns (MockERC20) {
    return new MockERC20(name, symbol, decimals);
  }

  function deployMockWNative() internal returns (MockWNative) {
    return new MockWNative();
  }

  function deployMockChainLinkPriceOracle() internal returns (MockChainLinkPriceOracle) {
    return new MockChainLinkPriceOracle();
  }

  function deployMockWNativeRelayer() internal returns (MockWNativeRelayer) {
    return new MockWNativeRelayer(address(nativeToken));
  }
}
