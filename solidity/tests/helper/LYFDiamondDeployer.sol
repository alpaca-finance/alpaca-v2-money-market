// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYFDiamond } from "../../contracts/lyf/LYFDiamond.sol";

// facets
import { DiamondCutFacet, IDiamondCut } from "../../contracts/lyf/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "../../contracts/lyf/facets/DiamondLoupeFacet.sol";
import { LYFAdminFacet } from "../../contracts/lyf/facets/LYFAdminFacet.sol";
import { LYFCollateralFacet } from "../../contracts/lyf/facets/LYFCollateralFacet.sol";
import { LYFFarmFacet } from "../../contracts/lyf/facets/LYFFarmFacet.sol";
import { LYFLiquidationFacet } from "../../contracts/lyf/facets/LYFLiquidationFacet.sol";
import { LYFOwnershipFacet } from "../../contracts/lyf/facets/LYFOwnershipFacet.sol";
import { LYFViewFacet } from "../../contracts/lyf/facets/LYFViewFacet.sol";

// initializers
import { DiamondInit } from "../../contracts/lyf/initializers/DiamondInit.sol";
import { LYFInit } from "../../contracts/lyf/initializers/LYFInit.sol";

library LYFDiamondDeployer {
  function deployPoolDiamond(address _moneyMarket) internal returns (address) {
    // Deploy DimondCutFacet
    DiamondCutFacet diamondCutFacet = new DiamondCutFacet();

    // Deploy LYF
    LYFDiamond _lyfDiamond = new LYFDiamond(address(this), address(diamondCutFacet));

    deployAdminFacet(DiamondCutFacet(address(_lyfDiamond)));
    deployLYFCollateralFacet(DiamondCutFacet(address(_lyfDiamond)));
    deployFarmFacet(DiamondCutFacet(address(_lyfDiamond)));
    deployLYFLiquidationFacet(DiamondCutFacet(address(_lyfDiamond)));
    deployLYFOwnershipFacet(DiamondCutFacet(address(_lyfDiamond)));
    deployLYFViewFacet(DiamondCutFacet(address(_lyfDiamond)));

    initializeDiamond(DiamondCutFacet(address(_lyfDiamond)));
    initializeLYF(DiamondCutFacet(address(_lyfDiamond)), _moneyMarket);

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

  function initializeLYF(DiamondCutFacet diamondCutFacet, address _moneyMarket) internal {
    // Deploy DiamondInit
    LYFInit _initializer = new LYFInit();
    IDiamondCut.FacetCut[] memory facetCuts = new IDiamondCut.FacetCut[](0);

    // make lib diamond call init
    diamondCutFacet.diamondCut(
      facetCuts,
      address(_initializer),
      abi.encodeWithSelector(bytes4(keccak256("init(address)")), _moneyMarket)
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

    bytes4[] memory selectors = new bytes4[](7);
    selectors[0] = LYFFarmFacet.addFarmPosition.selector;
    selectors[1] = LYFFarmFacet.repay.selector;
    selectors[2] = LYFFarmFacet.accrueInterest.selector;
    selectors[3] = LYFFarmFacet.reducePosition.selector;
    selectors[4] = LYFFarmFacet.directAddFarmPosition.selector;
    selectors[5] = LYFFarmFacet.reinvest.selector;
    selectors[6] = LYFFarmFacet.repayWithCollat.selector;

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

    bytes4[] memory selectors = new bytes4[](13);
    selectors[0] = LYFAdminFacet.setOracle.selector;
    selectors[1] = LYFAdminFacet.setTreasury.selector;
    selectors[2] = LYFAdminFacet.setTokenConfigs.selector;
    selectors[3] = LYFAdminFacet.setLPConfigs.selector;
    selectors[4] = LYFAdminFacet.setDebtPoolId.selector;
    selectors[5] = LYFAdminFacet.setDebtPoolInterestModel.selector;
    selectors[6] = LYFAdminFacet.setReinvestorsOk.selector;
    selectors[7] = LYFAdminFacet.setLiquidationStratsOk.selector;
    selectors[8] = LYFAdminFacet.setLiquidatorsOk.selector;
    selectors[9] = LYFAdminFacet.setMaxNumOfToken.selector;
    selectors[10] = LYFAdminFacet.setMinDebtSize.selector;
    selectors[11] = LYFAdminFacet.withdrawReserve.selector;
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

    _selectors = new bytes4[](3);
    _selectors[0] = LYFCollateralFacet.addCollateral.selector;
    _selectors[1] = LYFCollateralFacet.removeCollateral.selector;
    _selectors[2] = LYFCollateralFacet.transferCollateral.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_collatFacet),
      IDiamondCut.FacetCutAction.Add,
      _selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_collatFacet, _selectors);
  }

  function deployLYFLiquidationFacet(DiamondCutFacet diamondCutFacet)
    internal
    returns (LYFLiquidationFacet _liquidationFacet, bytes4[] memory _selectors)
  {
    _liquidationFacet = new LYFLiquidationFacet();

    _selectors = new bytes4[](3);
    _selectors[0] = LYFLiquidationFacet.repurchase.selector;
    _selectors[1] = LYFLiquidationFacet.lpLiquidationCall.selector;
    _selectors[2] = LYFLiquidationFacet.liquidationCall.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_liquidationFacet),
      IDiamondCut.FacetCutAction.Add,
      _selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_liquidationFacet, _selectors);
  }

  function deployLYFOwnershipFacet(DiamondCutFacet diamondCutFacet)
    internal
    returns (LYFOwnershipFacet _ownershipFacet, bytes4[] memory _selectors)
  {
    _ownershipFacet = new LYFOwnershipFacet();

    _selectors = new bytes4[](4);
    _selectors[0] = _ownershipFacet.transferOwnership.selector;
    _selectors[1] = _ownershipFacet.acceptOwnership.selector;
    _selectors[2] = _ownershipFacet.owner.selector;
    _selectors[3] = _ownershipFacet.pendingOwner.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_ownershipFacet),
      IDiamondCut.FacetCutAction.Add,
      _selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_ownershipFacet, _selectors);
  }

  function deployLYFViewFacet(DiamondCutFacet diamondCutFacet)
    internal
    returns (LYFViewFacet _viewFacet, bytes4[] memory _selectors)
  {
    _viewFacet = new LYFViewFacet();

    _selectors = new bytes4[](24);
    _selectors[0] = LYFViewFacet.getOracle.selector;
    _selectors[1] = LYFViewFacet.getLpTokenConfig.selector;
    _selectors[2] = LYFViewFacet.getLpTokenAmount.selector;
    _selectors[3] = LYFViewFacet.getLpTokenShare.selector;
    _selectors[4] = LYFViewFacet.getAllSubAccountCollats.selector;
    _selectors[5] = LYFViewFacet.getTokenCollatAmount.selector;
    _selectors[6] = LYFViewFacet.getSubAccountTokenCollatAmount.selector;
    _selectors[7] = LYFViewFacet.getMMDebt.selector;
    _selectors[8] = LYFViewFacet.getDebtPoolInfo.selector;
    _selectors[9] = LYFViewFacet.getDebtPoolTotalValue.selector;
    _selectors[10] = LYFViewFacet.getDebtPoolTotalShare.selector;
    _selectors[11] = LYFViewFacet.getSubAccountDebt.selector;
    _selectors[12] = LYFViewFacet.getAllSubAccountDebtShares.selector;
    _selectors[13] = LYFViewFacet.getDebtPoolLastAccruedAt.selector;
    _selectors[14] = LYFViewFacet.getDebtPoolPendingInterest.selector;
    _selectors[15] = LYFViewFacet.getPendingReward.selector;
    _selectors[16] = LYFViewFacet.getTotalBorrowingPower.selector;
    _selectors[17] = LYFViewFacet.getTotalUsedBorrowingPower.selector;
    _selectors[18] = LYFViewFacet.getMaxNumOfToken.selector;
    _selectors[19] = LYFViewFacet.getMinDebtSize.selector;
    _selectors[20] = LYFViewFacet.getOutstandingBalanceOf.selector;
    _selectors[21] = LYFViewFacet.getProtocolReserveOf.selector;
    _selectors[22] = LYFViewFacet.getSubAccount.selector;
    _selectors[23] = LYFViewFacet.getDebtPoolIdOf.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_viewFacet),
      IDiamondCut.FacetCutAction.Add,
      _selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_viewFacet, _selectors);
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
