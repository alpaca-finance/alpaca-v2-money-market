// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { AVDiamond } from "../../contracts/automated-vault/AVDiamond.sol";

// facets
import { DiamondCutFacet, IDiamondCut } from "../../contracts/automated-vault/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "../../contracts/automated-vault/facets/DiamondLoupeFacet.sol";
import { AVAdminFacet } from "../../contracts/automated-vault/facets/AVAdminFacet.sol";

// initializers
import { DiamondInit } from "../../contracts/automated-vault/initializers/DiamondInit.sol";

library AVDiamondDeployer {
  function deployPoolDiamond() internal returns (address _avDiamondAddr) {
    // Deploy DimondCutFacet
    DiamondCutFacet diamondCutFacet = new DiamondCutFacet();

    // Deploy Diamond
    AVDiamond _avDiamond = new AVDiamond(address(this), address(diamondCutFacet));
    _avDiamondAddr = address(_avDiamond);
    DiamondCutFacet _avDiamondCutFacet = DiamondCutFacet(_avDiamondAddr);

    // Initialize Diamond
    initializeDiamond(_avDiamondCutFacet);

    // Deploy Facets
    deployAdminFacet(_avDiamondCutFacet);
  }

  function initializeDiamond(DiamondCutFacet diamondCutFacet) internal {
    // Deploy DiamondInit
    DiamondInit diamondInitializer = new DiamondInit();
    IDiamondCut.FacetCut[] memory facetCuts = new IDiamondCut.FacetCut[](0);

    // make lib diamond call init
    diamondCutFacet.diamondCut(
      facetCuts,
      address(diamondInitializer),
      abi.encodeWithSelector(bytes4(keccak256("init()")))
    );
  }

  function deployDiamondLoupeFacet(DiamondCutFacet diamondCutFacet)
    internal
    returns (DiamondLoupeFacet, bytes4[] memory)
  {
    DiamondLoupeFacet _diamondLoupeFacet = new DiamondLoupeFacet();

    bytes4[] memory selectors = new bytes4[](4);
    selectors[0] = DiamondLoupeFacet.facets.selector;
    selectors[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
    selectors[2] = DiamondLoupeFacet.facetAddresses.selector;
    selectors[3] = DiamondLoupeFacet.facetAddress.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_diamondLoupeFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_diamondLoupeFacet, selectors);
  }

  function deployAdminFacet(DiamondCutFacet diamondCutFacet) internal returns (AVAdminFacet, bytes4[] memory) {
    AVAdminFacet _adminFacet = new AVAdminFacet();

    bytes4[] memory selectors = new bytes4[](2);
    selectors[0] = AVAdminFacet.setId.selector;
    selectors[1] = AVAdminFacet.getId.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_adminFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_adminFacet, selectors);
  }

  function buildFacetCut(
    address facet,
    IDiamondCut.FacetCutAction cutAction,
    bytes4[] memory selectors
  ) internal pure returns (IDiamondCut.FacetCut[] memory) {
    IDiamondCut.FacetCut[] memory facetCuts = new IDiamondCut.FacetCut[](1);
    facetCuts[0] = IDiamondCut.FacetCut({ action: cutAction, facetAddress: facet, functionSelectors: selectors });

    return facetCuts;
  }
}
