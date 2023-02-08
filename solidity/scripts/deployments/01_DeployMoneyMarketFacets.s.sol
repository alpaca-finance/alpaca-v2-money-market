// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "./BaseDeploymentScript.sol";

import { LibMoneyMarketDeployment } from "./libraries/LibMoneyMarketDeployment.sol";

contract DeployMoneyMarketFacetsScript is BaseDeploymentScript {
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
    facetsJson.serialize("diamondCutFacet", _facetAddresses.diamondCutFacet);
    facetsJson.serialize("diamondLoupeFacet", _facetAddresses.diamondLoupeFacet);
    facetsJson.serialize("viewFacet", _facetAddresses.viewFacet);
    facetsJson.serialize("lendFacet", _facetAddresses.lendFacet);
    facetsJson.serialize("collateralFacet", _facetAddresses.collateralFacet);
    facetsJson.serialize("borrowFacet", _facetAddresses.borrowFacet);
    facetsJson.serialize("nonCollatBorrowFacet", _facetAddresses.nonCollatBorrowFacet);
    facetsJson.serialize("adminFacet", _facetAddresses.adminFacet);
    facetsJson.serialize("liquidationFacet", _facetAddresses.liquidationFacet);
    facetsJson = facetsJson.serialize("ownershipFacet", _facetAddresses.ownershipFacet);

    // this will overwrite .MoneyMarket.Facets key in config file
    facetsJson.write(configFilePath, ".MoneyMarket.Facets");
  }
}
