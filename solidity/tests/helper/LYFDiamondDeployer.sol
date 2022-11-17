// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYFDiamond } from "../../contracts/lyf/LYFDiamond.sol";

// facets
import { DiamondCutFacet, IDiamondCut } from "../../contracts/lyf/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "../../contracts/lyf/facets/DiamondLoupeFacet.sol";
import { LYFAdminFacet } from "../../contracts/lyf/facets/LYFAdminFacet.sol";
import { LYFCollateralFacet } from "../../contracts/lyf/facets/LYFCollateralFacet.sol";
import { LYFFarmFacet } from "../../contracts/lyf/facets/LYFFarmFacet.sol";

// initializers
import { DiamondInit } from "../../contracts/lyf/initializers/DiamondInit.sol";

library LYFDiamondDeployer {
  function deployPoolDiamond() internal returns (address) {
    // Deploy DimondCutFacet
    DiamondCutFacet diamondCutFacet = new DiamondCutFacet();

    // Deploy LYF
    LYFDiamond _lyfDiamond = new LYFDiamond(address(this), address(diamondCutFacet));

    deployAdminFacet(DiamondCutFacet(address(_lyfDiamond)));
    deployLYFCollateralFacet(DiamondCutFacet(address(_lyfDiamond)));
    deployFarmFacet(DiamondCutFacet(address(_lyfDiamond)));

    initializeDiamond(DiamondCutFacet(address(_lyfDiamond)));

    return (address(_lyfDiamond));
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

  function deployFarmFacet(DiamondCutFacet diamondCutFacet) internal returns (LYFFarmFacet, bytes4[] memory) {
    LYFFarmFacet _farmFacet = new LYFFarmFacet();

    bytes4[] memory selectors = new bytes4[](13);
    selectors[0] = LYFFarmFacet.addFarmPosition.selector;
    selectors[1] = LYFFarmFacet.getDebtShares.selector;
    selectors[2] = LYFFarmFacet.getTotalBorrowingPower.selector;
    selectors[3] = LYFFarmFacet.getTotalUsedBorrowedPower.selector;
    selectors[4] = LYFFarmFacet.getDebt.selector;
    selectors[5] = LYFFarmFacet.repay.selector;
    selectors[6] = LYFFarmFacet.getGlobalDebt.selector;
    selectors[7] = LYFFarmFacet.debtLastAccureTime.selector;
    selectors[8] = LYFFarmFacet.pendingInterest.selector;
    selectors[9] = LYFFarmFacet.accureInterest.selector;
    selectors[10] = LYFFarmFacet.debtValues.selector;
    selectors[11] = LYFFarmFacet.debtShares.selector;
    selectors[12] = LYFFarmFacet.liquidateLP.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_farmFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_farmFacet, selectors);
  }

  function deployAdminFacet(DiamondCutFacet diamondCutFacet) internal returns (LYFAdminFacet, bytes4[] memory) {
    LYFAdminFacet _adminFacet = new LYFAdminFacet();

    bytes4[] memory selectors = new bytes4[](4);
    selectors[0] = LYFAdminFacet.setOracle.selector;
    selectors[1] = LYFAdminFacet.oracle.selector;
    selectors[2] = LYFAdminFacet.setTokenConfigs.selector;
    selectors[3] = LYFAdminFacet.setMoneyMarket.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_adminFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_adminFacet, selectors);
  }

  function deployLYFCollateralFacet(DiamondCutFacet diamondCutFacet)
    internal
    returns (LYFCollateralFacet _collatFacet, bytes4[] memory _selectors)
  {
    _collatFacet = new LYFCollateralFacet();

    _selectors = new bytes4[](5);
    _selectors[0] = LYFCollateralFacet.addCollateral.selector;
    _selectors[1] = LYFCollateralFacet.removeCollateral.selector;
    _selectors[2] = LYFCollateralFacet.collats.selector;
    _selectors[3] = LYFCollateralFacet.subAccountCollatAmount.selector;
    _selectors[4] = LYFCollateralFacet.getCollaterals.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_collatFacet),
      IDiamondCut.FacetCutAction.Add,
      _selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_collatFacet, _selectors);
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
