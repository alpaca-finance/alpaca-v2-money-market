// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { Script, console } from "solidity/tests/utils/Script.sol";
import "solidity/tests/utils/StdJson.sol";

import { LibMoneyMarketDeployment } from "../libraries/LibMoneyMarketDeployment.sol";

contract DeployMoneyMarket is Script {
  using stdJson for string;

  struct DeploymentConfig {
    address wNativeAddress;
    address wNativeRelayer;
  }

  function run() public {
    string memory configFilePath = string.concat(
      vm.projectRoot(),
      string.concat("/configs/", vm.envString("DEPLOYMENT_CONFIG_FILENAME"))
    );
    string memory configJson = vm.readFile(configFilePath);
    DeploymentConfig memory config = abi.decode(configJson.parseRaw("deploymentConfig"), (DeploymentConfig));

    vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
    (address moneyMarket, LibMoneyMarketDeployment.FacetAddresses memory facetAddresses) = LibMoneyMarketDeployment
      .deployMoneyMarket(config.wNativeAddress, config.wNativeRelayer);
    vm.stopBroadcast();

    // write deployed addresses to json
    // NOTE: can't specify order of keys
    string memory moneyMarketKey = "moneyMarket";
    vm.serializeAddress(moneyMarketKey, "MoneyMarket", moneyMarket);
    string memory facetsKey = "FacetAddresses";
    vm.serializeAddress(facetsKey, "DiamondCutFacet", facetAddresses.diamondCutFacet);
    vm.serializeAddress(facetsKey, "DiamondLoupeFacet", facetAddresses.diamondLoupeFacet);
    vm.serializeAddress(facetsKey, "ViewFacet", facetAddresses.viewFacet);
    vm.serializeAddress(facetsKey, "LendFacet", facetAddresses.lendFacet);
    vm.serializeAddress(facetsKey, "CollateralFacet", facetAddresses.collateralFacet);
    vm.serializeAddress(facetsKey, "BorrowFacet", facetAddresses.borrowFacet);
    vm.serializeAddress(facetsKey, "NonCollatBorrowFacet", facetAddresses.nonCollatBorrowFacet);
    vm.serializeAddress(facetsKey, "AdminFacet", facetAddresses.adminFacet);
    vm.serializeAddress(facetsKey, "LiquidationFacet", facetAddresses.liquidationFacet);
    vm.serializeAddress(facetsKey, "OwnershipFacet", facetAddresses.ownershipFacet);
    string memory facetsObject = vm.serializeAddress(facetsKey, "OwnershipFacet", facetAddresses.ownershipFacet);
    string memory finalJson = vm.serializeString(moneyMarketKey, "Facets", facetsObject);

    // this will overwrite existing json
    vm.writeJson(finalJson, "deployedAddresses.json");
  }
}
