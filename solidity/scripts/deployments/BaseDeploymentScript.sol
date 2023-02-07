// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { Script, console } from "solidity/tests/utils/Script.sol";
import "solidity/tests/utils/StdJson.sol";

import { LibMoneyMarketDeployment } from "./libraries/LibMoneyMarketDeployment.sol";
import { IAdminFacet } from "solidity/contracts/money-market/interfaces/IAdminFacet.sol";
import { IViewFacet } from "solidity/contracts/money-market/interfaces/IViewFacet.sol";

interface IMoneyMarket is IAdminFacet, IViewFacet {}

abstract contract BaseDeploymentScript is Script {
  using stdJson for string;

  struct DeploymentConfig {
    address wNativeAddress;
    address wNativeRelayer;
  }

  struct MoneyMarketConfig {
    address MoneyMarketDiamond;
    LibMoneyMarketDeployment.FacetAddresses Facets;
  }

  uint256 internal deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
  string internal configFilePath =
    string.concat(vm.projectRoot(), string.concat("/configs/", vm.envString("DEPLOYMENT_CONFIG_FILENAME")));

  DeploymentConfig internal deploymentConfig;
  MoneyMarketConfig internal moneyMarketConfig;
  address internal deployerAddress;

  function run() public {
    _setUp();
    _run();
  }

  /// @dev to run script locally pass flag --sig "runLocal()"
  function runLocal() public {
    _setUpForLocalRun();
    _run();
  }

  //
  // setups
  //

  /// @dev setUp for actual script runs
  function _setUp() internal {
    deploymentConfig = _getDeploymentConfig();
    moneyMarketConfig = _getMoneyMarketConfig();
    deployerAddress = vm.addr(deployerPrivateKey);
    console.log("addresses");
    console.log("  deployer :", deployerAddress);
  }

  /// @dev setUp for local run in case that haven't deployed mm to network yet
  function _setUpForLocalRun() internal virtual {
    deploymentConfig = _getDeploymentConfig();
    moneyMarketConfig = _getMoneyMarketConfig();
    deployerAddress = vm.addr(deployerPrivateKey);
    console.log("addresses");
    console.log("  deployer     :", deployerAddress);
  }

  //
  // utilities
  //

  function _getDeploymentConfig() internal returns (DeploymentConfig memory) {
    console.log("load deployment config from", configFilePath);
    string memory configJson = vm.readFile(configFilePath);
    return abi.decode(configJson.parseRaw("DeploymentConfig"), (DeploymentConfig));
  }

  function _getMoneyMarketConfig() internal returns (MoneyMarketConfig memory) {
    console.log("load money market config from", configFilePath);
    string memory configJson = vm.readFile(configFilePath);
    return abi.decode(configJson.parseRaw("MoneyMarket"), (MoneyMarketConfig));
  }

  function _startDeployerBroadcast() internal {
    vm.startBroadcast(deployerPrivateKey);
    console.log("");
    console.log("==== start broadcast as deployer ====");
  }

  function _stopBroadcast() internal {
    vm.stopBroadcast();
    console.log("==== broadcast stopped ====\n");
  }

  function _run() internal virtual;
}
