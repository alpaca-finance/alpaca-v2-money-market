// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { DSTest } from "solidity/tests/base/DSTest.sol";
import "../utils/Components.sol";
import { ProxyAdminLike } from "../interfaces/ProxyAdminLike.sol";

// implementation
import { PCSV3PathReader } from "solidity/contracts/reader/PCSV3PathReader.sol";

// interfaces
import { IERC20 } from "solidity/contracts/money-market/interfaces/IERC20.sol";
import { IPancakeSwapRouterV3 } from "solidity/contracts/money-market/interfaces/IPancakeSwapRouterV3.sol";
import { ISmartTreasury } from "solidity/contracts/smart-treasury/ISmartTreasury.sol";

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

  // Treasury
  address REVENUE_TREASURY = makeAddr("REVENUE_TREASURY");
  address DEV_TREASURY = makeAddr("DEV_TREASURY");
  address BURN_TREASURY = makeAddr("BURN_TREASURY");

  // Token
  IERC20 public constant wbnb = IERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
  IERC20 public constant usdt = IERC20(0x55d398326f99059fF775485246999027B3197955);
  IERC20 public constant cake = IERC20(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);

  IPancakeSwapRouterV3 internal router = IPancakeSwapRouterV3(0x1b81D678ffb9C0263b24A97847620C99d213eB14);
  PCSV3PathReader internal pathReader;
  ISmartTreasury internal smartTreasury;

  function setUp() public virtual {
    vm.createSelectFork("bsc_mainnet", 27_515_914);

    pathReader = new PCSV3PathReader();
    vm.startPrank(DEPLOYER);
    _setupProxyAdmin();
    smartTreasury = deploySmartTreasury(address(router), address(pathReader));
    vm.stopPrank();

    vm.label(address(wbnb), "WBNB");
    vm.label(address(usdt), "USDT");
    vm.label(address(cake), "CAKE");

    vm.label(ALICE, "ALICE");
    vm.label(BOB, "BOB");
    vm.label(CHARLIE, "CHARLIE");
    vm.label(EVE, "EVE");

    vm.label(REVENUE_TREASURY, "REVENUE_TREASURY");
    vm.label(DEV_TREASURY, "DEV_TREASURY");
    vm.label(BURN_TREASURY, "BURN_TREASURY");

    vm.label(address(router), "PancakeSwapRouterV3");
    vm.label(address(smartTreasury), "SmartTreasury");
  }

  function deployUpgradeable(string memory contractName, bytes memory initializer) internal returns (address) {
    // Deploy implementation contract
    bytes memory logicBytecode = abi.encodePacked(
      vm.getCode(string(abi.encodePacked("./out/", contractName, ".sol/", contractName, ".json")))
    );
    address logic;
    assembly {
      logic := create(0, add(logicBytecode, 0x20), mload(logicBytecode))
    }

    // Deploy proxy
    bytes memory proxyBytecode = abi.encodePacked(
      vm.getCode("./out/TransparentUpgradeableProxy.sol/TransparentUpgradeableProxy.json")
    );
    proxyBytecode = abi.encodePacked(proxyBytecode, abi.encode(logic, address(proxyAdmin), initializer));

    address proxy;
    assembly {
      proxy := create(0, add(proxyBytecode, 0x20), mload(proxyBytecode))
      if iszero(extcodesize(proxy)) {
        revert(0, 0)
      }
    }

    return proxy;
  }

  function _setupProxyAdmin() internal returns (ProxyAdminLike) {
    bytes memory _bytecode = abi.encodePacked(vm.getCode("./out/ProxyAdmin.sol/ProxyAdmin.json"));
    address _address;
    assembly {
      _address := create(0, add(_bytecode, 0x20), mload(_bytecode))
    }
    return ProxyAdminLike(address(_address));
  }

  function deploySmartTreasury(address _router, address _pathReader) internal returns (ISmartTreasury) {
    return
      ISmartTreasury(
        deployUpgradeable(
          "SmartTreasury",
          abi.encodeWithSelector(bytes4(keccak256("initialize(address,address)")), _router, _pathReader)
        )
      );
  }

  function normalizeEther(uint256 _ether, uint256 _decimal) internal pure returns (uint256 _normalizedEther) {
    _normalizedEther = _ether / 10**(18 - _decimal);
  }
}
