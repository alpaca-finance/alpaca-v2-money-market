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

// mocks
import { MockERC20 } from "solidity/tests/mocks/MockERC20.sol";

interface IMoneyMarket is IAdminFacet, IViewFacet, ICollateralFacet, IBorrowFacet, ILendFacet {}

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
    address MoneyMarketDiamond;
    LibMoneyMarketDeployment.FacetAddresses Facets;
  }

  function _setUp() internal {
    MoneyMarketConfig memory mmConfig = _getMoneyMarketConfig();
    address _moneyMarketDiamond = mmConfig.MoneyMarketDiamond;
    // setup mm if not exist for local simulation
    uint256 size;
    assembly {
      size := extcodesize(_moneyMarketDiamond)
    }
    if (size > 0) {
      moneyMarket = IMoneyMarket(_moneyMarketDiamond);
    } else {
      (_moneyMarketDiamond, ) = LibMoneyMarketDeployment.deployMoneyMarketDiamond(address(1), address(2));
      moneyMarket = IMoneyMarket(_moneyMarketDiamond);
    }

    deployerAddress = vm.addr(deployerPrivateKey);
    userAddress = vm.addr(userPrivateKey);

    console.log("addresses");
    console.log("  deployer     :", deployerAddress);
    console.log("  user     :", userAddress);
    console.log("  money market :", address(moneyMarket));
  }

  function _setUpMockToken() internal returns (address) {
    return address(new MockERC20("", "TEST", 18));
  }

  function _getDeploymentConfig() internal view returns (DeploymentConfig memory) {
    console.log("load deployment config from", configFilePath);
    string memory configJson = vm.readFile(configFilePath);
    return abi.decode(configJson.parseRaw("deploymentConfig"), (DeploymentConfig));
  }

  function _getMoneyMarketConfig() internal view returns (MoneyMarketConfig memory) {
    console.log("load money market config from", configFilePath);
    string memory configJson = vm.readFile(configFilePath);
    return abi.decode(configJson.parseRaw("moneyMarket"), (MoneyMarketConfig));
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
