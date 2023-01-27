// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { Script, console } from "solidity/tests/utils/Script.sol";

import { LibMoneyMarketDeployment } from "../libraries/LibMoneyMarketDeployment.sol";

contract DeployMoneyMarket is Script {
  function run() public {
    vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
    (address moneyMarket, LibMoneyMarketDeployment.FacetAddresses memory facetAddresses) = LibMoneyMarketDeployment
      .deployMoneyMarket(address(1), address(2));
    vm.stopBroadcast();

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

    vm.writeJson(finalJson, "test.json");
  }
}
