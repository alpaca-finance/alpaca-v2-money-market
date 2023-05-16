// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { DSTest } from "solidity/tests/base/DSTest.sol";
import "../utils/Components.sol";
import { ProxyAdminLike } from "../interfaces/ProxyAdminLike.sol";

// implementation
import { PCSV3PathReader } from "solidity/contracts/reader/PCSV3PathReader.sol";
import { PCSV2PathReader } from "solidity/contracts/reader/PCSV2PathReader.sol";
import { SmartTreasury } from "solidity/contracts/smart-treasury/SmartTreasury.sol";

// interfaces
import { IERC20 } from "solidity/contracts/money-market/interfaces/IERC20.sol";
import { IPancakeSwapRouterV3 } from "solidity/contracts/money-market/interfaces/IPancakeSwapRouterV3.sol";
import { IPancakeRouter02 } from "solidity/contracts/money-market/interfaces/IPancakeRouter02.sol";
import { IQuoterV2 } from "solidity/tests/interfaces/IQuoterV2.sol";
import { IOracleMedianizer } from "solidity/contracts/oracle/interfaces/IOracleMedianizer.sol";

contract BaseFork is DSTest, StdUtils, StdAssertions, StdCheats {
  using stdStorage for StdStorage;

  VM internal constant vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

  ProxyAdminLike internal proxyAdmin;

  // Users
  address constant DEPLOYER = 0xC44f82b07Ab3E691F826951a6E335E1bC1bB0B51;
  address ALICE = makeAddr("ALICE");
  address BOB = makeAddr("BOB");
  address CHARLIE = makeAddr("CHARLIE");
  address EVE = makeAddr("EVE");

  address internal constant PANCAKE_V3_POOL_DEPLOYER = 0x41ff9AA7e16B8B1a8a8dc4f0eFacd93D02d071c9;

  // Treasury
  address REVENUE_TREASURY = makeAddr("REVENUE_TREASURY");
  address DEV_TREASURY = makeAddr("DEV_TREASURY");
  address BURN_TREASURY = makeAddr("BURN_TREASURY");

  // Token

  IERC20 public constant btcb = IERC20(0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c);
  IERC20 public constant eth = IERC20(0x2170Ed0880ac9A755fd29B2688956BD959F933F8);
  IERC20 public constant wbnb = IERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
  IERC20 public constant usdt = IERC20(0x55d398326f99059fF775485246999027B3197955);
  IERC20 public constant usdc = IERC20(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d);
  IERC20 public constant cake = IERC20(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
  IERC20 public constant doge = IERC20(0xbA2aE424d960c26247Dd6c32edC70B295c744C43);

  address internal usd = 0x115dffFFfffffffffFFFffffFFffFfFfFFFFfFff;

  IPancakeRouter02 internal routerV2 = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
  IPancakeSwapRouterV3 internal routerV3 = IPancakeSwapRouterV3(0x1b81D678ffb9C0263b24A97847620C99d213eB14);
  PCSV2PathReader internal pathReaderV2;
  PCSV3PathReader internal pathReaderV3;
  SmartTreasury internal smartTreasury;
  IQuoterV2 internal quoterV2 = IQuoterV2(0xB048Bbc1Ee6b733FFfCFb9e9CeF7375518e25997);
  IOracleMedianizer internal oracleMedianizer = IOracleMedianizer(0x553b8adc2Ac16491Ec57239BeA7191719a2B880c);

  function setUp() public virtual {
    vm.createSelectFork("bsc_mainnet", 28_113_725);

    pathReaderV2 = new PCSV2PathReader();
    pathReaderV3 = new PCSV3PathReader();

    // set path v3
    bytes[] memory _paths = new bytes[](2);
    _paths[0] = abi.encodePacked(address(wbnb), uint24(500), address(usdt));
    _paths[1] = abi.encodePacked(address(eth), uint24(500), address(usdc), uint24(100), address(usdt));

    pathReaderV3.setPaths(_paths);

    vm.startPrank(DEPLOYER);
    proxyAdmin = _setupProxyAdmin();
    smartTreasury = deploySmartTreasury(
      address(pathReaderV2),
      address(routerV3),
      address(pathReaderV3),
      address(oracleMedianizer)
    );
    vm.stopPrank();

    vm.label(address(eth), "ETH");
    vm.label(address(wbnb), "WBNB");
    vm.label(address(usdt), "USDT");
    vm.label(address(usdc), "USDC");
    vm.label(address(cake), "CAKE");
    vm.label(address(doge), "DOGE");

    vm.label(ALICE, "ALICE");
    vm.label(BOB, "BOB");
    vm.label(CHARLIE, "CHARLIE");
    vm.label(EVE, "EVE");

    vm.label(REVENUE_TREASURY, "REVENUE_TREASURY");
    vm.label(DEV_TREASURY, "DEV_TREASURY");
    vm.label(BURN_TREASURY, "BURN_TREASURY");

    vm.label(address(routerV3), "PancakeSwapRouterV3");
    vm.label(address(routerV2), "PancakeSwapRouterV2");
    vm.label(address(smartTreasury), "SmartTreasury");
    vm.label(address(oracleMedianizer), "OracleMedianizer");
  }

  function deploySmartTreasury(
    address _pathReaderV2,
    address _routerV3,
    address _pathReaderV3,
    address _oracle
  ) internal returns (SmartTreasury) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/SmartTreasury.sol/SmartTreasury.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,address,address)")),
      _pathReaderV2,
      _routerV3,
      _pathReaderV3,
      _oracle
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer);
    return SmartTreasury(_proxy);
  }

  function _setupUpgradeable(bytes memory _logicBytecode, bytes memory _initializer) internal returns (address) {
    bytes memory _proxyBytecode = abi.encodePacked(
      vm.getCode("./out/TransparentUpgradeableProxy.sol/TransparentUpgradeableProxy.json")
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
