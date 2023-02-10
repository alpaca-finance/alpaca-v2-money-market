// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "solidity/tests/utils/StdJson.sol";
import { Script, console } from "solidity/tests/utils/Script.sol";

// libs
import { LibMoneyMarketDeployment } from "./deployments/libraries/LibMoneyMarketDeployment.sol";

// interfaces
import { IAdminFacet } from "solidity/contracts/money-market/interfaces/IAdminFacet.sol";
import { IViewFacet } from "solidity/contracts/money-market/interfaces/IViewFacet.sol";
import { ICollateralFacet } from "solidity/contracts/money-market/interfaces/ICollateralFacet.sol";
import { IBorrowFacet } from "solidity/contracts/money-market/interfaces/IBorrowFacet.sol";
import { ILendFacet } from "solidity/contracts/money-market/interfaces/ILendFacet.sol";
import { IOwnershipFacet } from "solidity/contracts/money-market/interfaces/IOwnershipFacet.sol";

// mocks
import { MockERC20 } from "solidity/tests/mocks/MockERC20.sol";

interface IMoneyMarket is IAdminFacet, IViewFacet, ICollateralFacet, IBorrowFacet, ILendFacet, IOwnershipFacet {}

abstract contract BaseScript is Script {
  using stdJson for string;

  uint256 internal deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
  uint256 internal userPrivateKey = vm.envUint("USER_PRIVATE_KEY");
  string internal configFilePath =
    string.concat(vm.projectRoot(), string.concat("/configs/", vm.envString("DEPLOYMENT_CONFIG_FILENAME")));

  IMoneyMarket internal moneyMarket;
  address internal deployerAddress;
  address internal userAddress;

  struct DeploymentConfig {
    address wNativeAddress;
    address wNativeRelayer;
  }

  struct MoneyMarketConfig {
    address moneyMarketDiamond;
  }

  function _setUp() internal {
    deployerAddress = vm.addr(deployerPrivateKey);
    userAddress = vm.addr(userPrivateKey);

    MoneyMarketConfig memory mmConfig = _getMoneyMarketConfig();
    address _moneyMarketDiamond = mmConfig.moneyMarketDiamond;
    // setup mm if not exist for local simulation
    uint256 size;
    assembly {
      size := extcodesize(_moneyMarketDiamond)
    }
    if (size > 0) {
      moneyMarket = IMoneyMarket(_moneyMarketDiamond);
    } else {
      vm.startPrank(deployerAddress);
      (_moneyMarketDiamond, ) = LibMoneyMarketDeployment.deployMoneyMarketDiamond(address(1), address(2));
      vm.stopPrank();
      moneyMarket = IMoneyMarket(_moneyMarketDiamond);
    }

    console.log("addresses");
    console.log("  deployer     :", deployerAddress);
    console.log("  user     :", userAddress);
    console.log("  money market :", address(moneyMarket));
  }

  function _setUpMockToken(string memory symbol, uint8 decimals) internal returns (address) {
    address newToken = address(new MockERC20("", symbol, decimals));
    vm.label(newToken, symbol);
    return newToken;
  }

  function _getDeploymentConfig() internal view returns (DeploymentConfig memory config) {
    console.log("load deployment config from", configFilePath);
    string memory configJson = vm.readFile(configFilePath);
    config.wNativeAddress = abi.decode(configJson.parseRaw(".deploymentConfig.wNativeAddress"), (address));
    config.wNativeRelayer = abi.decode(configJson.parseRaw(".deploymentConfig.wNativeRelayer"), (address));
  }

  function _getMoneyMarketConfig() internal view returns (MoneyMarketConfig memory config) {
    console.log("load money market config from", configFilePath);
    string memory configJson = vm.readFile(configFilePath);
    config.moneyMarketDiamond = abi.decode(configJson.parseRaw(".moneyMarket.moneyMarketDiamond"), (address));
  }

  function _startDeployerBroadcast() internal {
    vm.startBroadcast(deployerPrivateKey);
    console.log("");
    console.log("==== start broadcast as deployer ====");
  }

  function _startUserBroadcast() internal {
    vm.startBroadcast(userPrivateKey);
    console.log("");
    console.log("==== start broadcast as user ====");
  }

  function _stopBroadcast() internal {
    vm.stopBroadcast();
    console.log("==== broadcast stopped ====\n");
  }

  function _writeJson(string memory serializedJson, string memory path) internal {
    serializedJson.write(configFilePath, path);
  }
}
