// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "./BaseDeploymentScript.sol";

import { LibMoneyMarketDeployment } from "./libraries/LibMoneyMarketDeployment.sol";

contract DeployMoneyMarketFacets is BaseDeploymentScript {
  using stdJson for string;

  function _run() internal override {
    _startDeployerBroadcast();

    // deploy money market facets
    LibMoneyMarketDeployment.FacetAddresses memory _facetAddresses = LibMoneyMarketDeployment.deployMoneyMarketFacets();

    _stopBroadcast();

    // write deployed addresses to json
    // NOTE: can't specify order of keys

    // facets
    string memory facetsJson = "Facets";
    facetsJson.serialize("DiamondCutFacet", _facetAddresses.diamondCutFacet);
    facetsJson.serialize("DiamondLoupeFacet", _facetAddresses.diamondLoupeFacet);
    facetsJson.serialize("ViewFacet", _facetAddresses.viewFacet);
    facetsJson.serialize("LendFacet", _facetAddresses.lendFacet);
    facetsJson.serialize("CollateralFacet", _facetAddresses.collateralFacet);
    facetsJson.serialize("BorrowFacet", _facetAddresses.borrowFacet);
    facetsJson.serialize("NonCollatBorrowFacet", _facetAddresses.nonCollatBorrowFacet);
    facetsJson.serialize("AdminFacet", _facetAddresses.adminFacet);
    facetsJson.serialize("LiquidationFacet", _facetAddresses.liquidationFacet);
    facetsJson = facetsJson.serialize("OwnershipFacet", _facetAddresses.ownershipFacet);

    // this will overwrite .MoneyMarket.Facets key in config file
    facetsJson.write(configFilePath, ".MoneyMarket.Facets");
  }
}
