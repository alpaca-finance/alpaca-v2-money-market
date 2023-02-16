// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { DSTest } from "./DSTest.sol";

import { VM } from "../utils/VM.sol";
import { console } from "../utils/console.sol";

// interfaces
import { ProxyAdminLike } from "../interfaces/ProxyAdminLike.sol";
import { IMiniFL } from "../../contracts/miniFL/interfaces/IMiniFL.sol";
import { IPriceOracle } from "solidity/contracts/oracle/interfaces/IPriceOracle.sol";

// miniFL
import { MiniFL } from "../../contracts/miniFL/MiniFL.sol";
import { Rewarder } from "../../contracts/miniFL/Rewarder.sol";

// mm contract
import { InterestBearingToken } from "../../contracts/money-market/InterestBearingToken.sol";

// oracle
import { SimplePriceOracle } from "../../contracts/oracle/SimplePriceOracle.sol";
import { ChainLinkPriceOracle2 } from "../../contracts/oracle/ChainLinkPriceOracle2.sol";
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

  MockWNative internal wNativeToken;
  MockERC20 internal cake;
  MockERC20 internal weth;
  MockERC20 internal usdc;
  MockERC20 internal busd;
  MockERC20 internal btc;
  MockERC20 internal alpaca;
  address internal usd;
  MockERC20 internal isolateToken;

  uint256 internal wNativeTokenDecimal = 18;
  uint256 internal cakeDecimal;
  uint256 internal wethDecimal;
  uint256 internal usdcDecimal;
  uint256 internal busdDecimal;
  uint256 internal btcDecimal;
  uint256 internal usdDecimal = 18;
  uint256 internal isolateTokenDecimal;

  InterestBearingToken internal ibWeth;
  InterestBearingToken internal ibBtc;
  InterestBearingToken internal ibUsdc;
  InterestBearingToken internal ibIsolateToken;
  InterestBearingToken internal ibWNative;

  uint256 internal ibWethDecimal;
  uint256 internal ibBtcDecimal;
  uint256 internal ibUsdcDecimal;
  uint256 internal ibIsolateTokenDecimal;
  uint256 internal ibWNativeDecimal;

  MockERC20 internal debtToken1;

  MockERC20 internal rewardToken1;
  MockERC20 internal rewardToken2;

  IPriceOracle internal oracle;
  IAlpacaV2Oracle internal alpacaV2Oracle;
  OracleMedianizer internal oracleMedianizer;

  MockWNativeRelayer wNativeRelayer;

  ProxyAdminLike internal proxyAdmin;

  MiniFL internal miniFL;
  uint256 constant maxAlpacaPerSecond = 1000 ether;

  constructor() {
    // set block.timestamp be 100000
    vm.warp(100000);
    // deploy
    usd = address(0x115dffFFfffffffffFFFffffFFffFfFfFFFFfFff);
    wNativeToken = deployMockWNative();
    wNativeRelayer = deployMockWNativeRelayer();

    cake = deployMockErc20("CAKE", "CAKE", 18);
    weth = deployMockErc20("Wrapped Ethereum", "WETH", 18);
    btc = deployMockErc20("Bitcoin", "BTC", 18);
    usdc = deployMockErc20("USD COIN", "USDC", 6);
    busd = deployMockErc20("BUSD", "BUSD", 18);
    alpaca = deployMockErc20("ALPACA TOKEN", "ALPACA", 18);
    isolateToken = deployMockErc20("ISOLATETOKEN", "ISOLATETOKEN", 18);

    debtToken1 = deployMockErc20("Debt Token 1", "DTOKEN1", 18);

    rewardToken1 = deployMockErc20("Reward Token 1", "RTOKEN1", 18);
    rewardToken2 = deployMockErc20("Reward Token 2", "RTOKEN2", 6);

    cakeDecimal = cake.decimals();
    wethDecimal = weth.decimals();
    usdcDecimal = usdc.decimals();
    busdDecimal = busd.decimals();
    btcDecimal = btc.decimals();
    isolateTokenDecimal = isolateToken.decimals();

    // mint token
    vm.deal(ALICE, 1000 ether);

    weth.mint(ALICE, normalizeEther(1000 ether, wethDecimal));
    btc.mint(ALICE, normalizeEther(1000 ether, btcDecimal));
    usdc.mint(ALICE, normalizeEther(1000 ether, usdcDecimal));
    cake.mint(ALICE, normalizeEther(1000 ether, cakeDecimal));
    isolateToken.mint(ALICE, normalizeEther(1000 ether, isolateTokenDecimal));

    weth.mint(EVE, normalizeEther(1000 ether, wethDecimal));
    btc.mint(EVE, normalizeEther(1000 ether, btcDecimal));
    usdc.mint(EVE, normalizeEther(1000 ether, usdcDecimal));
    isolateToken.mint(EVE, normalizeEther(1000 ether, isolateTokenDecimal));

    weth.mint(BOB, normalizeEther(1000 ether, wethDecimal));
    btc.mint(BOB, normalizeEther(1000 ether, btcDecimal));
    usdc.mint(BOB, normalizeEther(1000 ether, usdcDecimal));
    isolateToken.mint(BOB, normalizeEther(1000 ether, isolateTokenDecimal));

    // miniFL

    _setupProxyAdmin();

    vm.label(DEPLOYER, "DEPLOYER");
    vm.label(ALICE, "ALICE");
    vm.label(BOB, "BOB");
    vm.label(CAT, "CAT");
    vm.label(EVE, "EVE");

    miniFL = deployMiniFL(address(alpaca), maxAlpacaPerSecond);
  }

  function deployMockErc20(
    string memory name,
    string memory symbol,
    uint8 decimals
  ) internal returns (MockERC20 mockERC20) {
    mockERC20 = new MockERC20(name, symbol, decimals);
    vm.label(address(mockERC20), symbol);
  }

  function deployMockWNative() internal returns (MockWNative) {
    return new MockWNative();
  }

  function deployMockChainLinkPriceOracle() internal returns (MockChainLinkPriceOracle) {
    return new MockChainLinkPriceOracle();
  }

  function deployMockWNativeRelayer() internal returns (MockWNativeRelayer) {
    return new MockWNativeRelayer(address(wNativeToken));
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

  function deployAlpacaV2Oracle(address _oracleMedianizer, address _baseStable) internal returns (AlpacaV2Oracle) {
    return new AlpacaV2Oracle(_oracleMedianizer, _baseStable, usd);
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

  function normalizeEther(uint256 _ether, uint256 _decimal) internal pure returns (uint256 _normalizedEther) {
    _normalizedEther = _ether / 10**(18 - _decimal);
  }
}
