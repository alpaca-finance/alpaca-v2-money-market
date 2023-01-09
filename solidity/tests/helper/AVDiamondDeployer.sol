// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { AVDiamond } from "../../contracts/automated-vault/AVDiamond.sol";

// facets
import { DiamondCutFacet, IDiamondCut } from "../../contracts/automated-vault/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "../../contracts/automated-vault/facets/DiamondLoupeFacet.sol";
import { AVAdminFacet } from "../../contracts/automated-vault/facets/AVAdminFacet.sol";
import { AVTradeFacet } from "../../contracts/automated-vault/facets/AVTradeFacet.sol";
import { AVViewFacet } from "../../contracts/automated-vault/facets/AVViewFacet.sol";

// initializers
import { DiamondInit } from "../../contracts/automated-vault/initializers/DiamondInit.sol";
import { AVInit } from "../../contracts/automated-vault/initializers/AVInit.sol";

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
    deployTradeFacet(_avDiamondCutFacet);
    deployViewFacet(_avDiamondCutFacet);
  }

  function initializeDiamond(DiamondCutFacet diamondCutFacet) internal {
    // Deploy DiamondInit
    AVInit _initializer = new AVInit();
    IDiamondCut.FacetCut[] memory facetCuts = new IDiamondCut.FacetCut[](0);

    // make lib diamond call init
    diamondCutFacet.diamondCut(facetCuts, address(_initializer), abi.encodeWithSelector(bytes4(keccak256("init()"))));
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

    bytes4[] memory selectors = new bytes4[](7);
    selectors[0] = AVAdminFacet.openVault.selector;
    selectors[1] = AVAdminFacet.setTokenConfigs.selector;
    selectors[2] = AVAdminFacet.setOracle.selector;
    selectors[3] = AVAdminFacet.setMoneyMarket.selector;
    selectors[4] = AVAdminFacet.setTreasury.selector;
    selectors[5] = AVAdminFacet.setManagementFeePerSec.selector;
    selectors[6] = AVAdminFacet.setInterestRateModels.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_adminFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_adminFacet, selectors);
  }

  function deployTradeFacet(DiamondCutFacet diamondCutFacet) internal returns (AVTradeFacet, bytes4[] memory) {
    AVTradeFacet _tradeFacet = new AVTradeFacet();

    bytes4[] memory selectors = new bytes4[](2);
    selectors[0] = AVTradeFacet.deposit.selector;
    selectors[1] = AVTradeFacet.withdraw.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_tradeFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_tradeFacet, selectors);
  }

  function deployViewFacet(DiamondCutFacet diamondCutFacet) internal returns (AVViewFacet, bytes4[] memory) {
    AVViewFacet _viewFacet = new AVViewFacet();

    bytes4[] memory selectors = new bytes4[](4);
    selectors[0] = AVViewFacet.getDebtValues.selector;
    selectors[1] = AVViewFacet.getVaultPendingInterest.selector;
    selectors[2] = AVViewFacet.getVaultLastAccrueInterestTimestamp.selector;
    selectors[3] = AVViewFacet.getPendingManagementFee.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_viewFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_viewFacet, selectors);
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
