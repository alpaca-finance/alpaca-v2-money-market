// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { DSTest } from "./DSTest.sol";

import { VM } from "../utils/VM.sol";
import { console } from "../utils/console.sol";

// interfaces
import { ProxyAdminLike } from "../interfaces/ProxyAdminLike.sol";
import { IMiniFL } from "../../contracts/miniFL/interfaces/IMiniFL.sol";

// miniFL
import { MiniFL } from "../../contracts/miniFL/MiniFL.sol";
import { Rewarder } from "../../contracts/miniFL/Rewarder.sol";

// oracle
import { SimplePriceOracle } from "../../contracts/oracle/SimplePriceOracle.sol";
import { ChainLinkPriceOracle2, IPriceOracle } from "../../contracts/oracle/ChainLinkPriceOracle2.sol";
import { AlpacaV2Oracle, IAlpacaV2Oracle } from "../../contracts/oracle/AlpacaV2Oracle.sol";
import { OracleMedianizer } from "../../contracts/oracle/OracleMedianizer.sol";

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
  MockERC20 internal cake;
  MockERC20 internal weth;
  MockERC20 internal usdc;
  MockERC20 internal btc;
  MockERC20 internal opm; // open market token
  MockERC20 internal alpaca;
  address internal usd;
  MockERC20 internal isolateToken;

  MockERC20 internal ibWeth;
  MockERC20 internal ibBtc;
  MockERC20 internal ibUsdc;
  MockERC20 internal ibIsolateToken;
  MockERC20 internal ibWNative;

  MockERC20 internal debtToken1;

  MockERC20 internal rewardToken1;
  MockERC20 internal rewardToken2;

  IPriceOracle internal oracle;
  IAlpacaV2Oracle internal alpacaV2Oracle;
  OracleMedianizer internal oracleMedianizer;

  MockWNativeRelayer nativeRelayer;

  ProxyAdminLike internal proxyAdmin;

  constructor() {
    // deploy
    cake = deployMockErc20("CAKE", "CAKE", 18);
    weth = deployMockErc20("Wrapped Ethereum", "WETH", 18);
    btc = deployMockErc20("Bitcoin", "BTC", 18);
    usdc = deployMockErc20("USD COIN", "USDC", 18);
    usd = address(0x115dffFFfffffffffFFFffffFFffFfFfFFFFfFff);
    opm = deployMockErc20("OPM Token", "OPM", 9);
    alpaca = deployMockErc20("ALPACA TOKEN", "ALPACA", 18);
    isolateToken = deployMockErc20("ISOLATETOKEN", "ISOLATETOKEN", 18);
    nativeToken = deployMockWNative();

    ibWeth = deployMockErc20("Interest Bearing Wrapped Ethereum", "IBWETH", 18);
    ibBtc = deployMockErc20("Interest Bearing Bitcoin", "IBBTC", 18);
    ibUsdc = deployMockErc20("Interest USD COIN", "IBUSDC", 18);
    ibIsolateToken = deployMockErc20("IBISOLATETOKEN", "IBISOLATETOKEN", 18);
    ibWNative = deployMockErc20("Interest Bearing WNATIVE", "WNATIVE", 18);

    debtToken1 = deployMockErc20("Debt Token 1", "DTOKEN1", 18);

    rewardToken1 = deployMockErc20("Reward Token 1", "RTOKEN1", 18);
    rewardToken2 = deployMockErc20("Reward Token 2", "RTOKEN2", 18);

    nativeRelayer = deployMockWNativeRelayer();

    // mint token
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

    // miniFL

    _setupProxyAdmin();
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

  function deployMiniFL(address _rewardToken, uint256 _rewardPerSec) internal returns (MiniFL) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/MiniFL.sol/MiniFL.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,uint256)")),
      _rewardToken,
      _rewardPerSec
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer);
    return MiniFL(_proxy);
  }

  function deployRewarder(
    string memory _name,
    address _miniFL,
    address _rewardToken,
    uint256 _maxRewardPerSecond
  ) internal returns (Rewarder) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/Rewarder.sol/Rewarder.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(string,address,address,uint256)")),
      _name,
      _miniFL,
      _rewardToken,
      _maxRewardPerSecond
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer);
    return Rewarder(_proxy);
  }

  function deployAlpacaV2Oracle(address _oracleMedianizer) internal returns (AlpacaV2Oracle) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/AlpacaV2Oracle.sol/AlpacaV2Oracle.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address)")),
      _oracleMedianizer,
      usd
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer);
    return AlpacaV2Oracle(_proxy);
  }

  function deployOracleMedianizer() internal returns (OracleMedianizer) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/OracleMedianizer.sol/OracleMedianizer.json"));
    bytes memory _initializer = abi.encodeWithSelector(bytes4(keccak256("initialize()")));
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer);
    return OracleMedianizer(_proxy);
  }

  function _setupUpgradeable(bytes memory _logicBytecode, bytes memory _initializer) internal returns (address) {
    bytes memory _proxyBytecode = abi.encodePacked(
      vm.getCode("./out/AdminUpgradeabilityProxy.sol/AdminUpgradeabilityProxy.json")
    );

    address _logic;
    assembly {
      _logic := create(0, add(_logicBytecode, 0x20), mload(_logicBytecode))
    }

    _proxyBytecode = abi.encodePacked(_proxyBytecode, abi.encode(_logic, address(proxyAdmin), _initializer));

    address _proxy;
    assembly {
      _proxy := create(0, add(_proxyBytecode, 0x20), mload(_proxyBytecode))
      if iszero(extcodesize(_proxy)) {
        revert(0, 0)
      }
    }

    return _proxy;
  }

  function _setupProxyAdmin() internal returns (ProxyAdminLike) {
    bytes memory _bytecode = abi.encodePacked(vm.getCode("./out/ProxyAdmin.sol/ProxyAdmin.json"));
    address _address;
    assembly {
      _address := create(0, add(_bytecode, 0x20), mload(_bytecode))
    }
    return ProxyAdminLike(address(_address));
  }
}
