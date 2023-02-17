// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// core
import { MoneyMarketDiamond } from "../../../contracts/money-market/MoneyMarketDiamond.sol";

// facets
import { DiamondCutFacet, IDiamondCut } from "../../../contracts/money-market/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "../../../contracts/money-market/facets/DiamondLoupeFacet.sol";
import { ViewFacet } from "../../../contracts/money-market/facets/ViewFacet.sol";
import { LendFacet } from "../../../contracts/money-market/facets/LendFacet.sol";
import { CollateralFacet } from "../../../contracts/money-market/facets/CollateralFacet.sol";
import { BorrowFacet } from "../../../contracts/money-market/facets/BorrowFacet.sol";
import { NonCollatBorrowFacet } from "../../../contracts/money-market/facets/NonCollatBorrowFacet.sol";
import { AdminFacet } from "../../../contracts/money-market/facets/AdminFacet.sol";
import { LiquidationFacet } from "../../../contracts/money-market/facets/LiquidationFacet.sol";
import { OwnershipFacet } from "../../../contracts/money-market/facets/OwnershipFacet.sol";

library LibMoneyMarketDeployment {
  struct FacetAddresses {
    address diamondCutFacet;
    address diamondLoupeFacet;
    address viewFacet;
    address lendFacet;
    address collateralFacet;
    address borrowFacet;
    address nonCollatBorrowFacet;
    address adminFacet;
    address liquidationFacet;
    address ownershipFacet;
  }

  function deployMoneyMarketDiamond(address _miniFL)
    internal
    returns (address _moneyMarketDiamond, FacetAddresses memory _facetAddresses)
  {
    // deploy facets
    _facetAddresses = deployMoneyMarketFacets();

    // deploy MoneyMarketDiamond
    _moneyMarketDiamond = address(new MoneyMarketDiamond(_facetAddresses.diamondCutFacet, _miniFL));

    // do diamondCut
    diamondCutAllMoneyMarketFacets(_moneyMarketDiamond, _facetAddresses);

    return (_moneyMarketDiamond, _facetAddresses);
  }

  function deployMoneyMarketFacets() internal returns (FacetAddresses memory _facetAddresses) {
    _facetAddresses.diamondCutFacet = address(new DiamondCutFacet());
    _facetAddresses.diamondLoupeFacet = address(new DiamondLoupeFacet());
    _facetAddresses.viewFacet = address(new ViewFacet());
    _facetAddresses.lendFacet = address(new LendFacet());
    _facetAddresses.collateralFacet = address(new CollateralFacet());
    _facetAddresses.borrowFacet = address(new BorrowFacet());
    _facetAddresses.nonCollatBorrowFacet = address(new NonCollatBorrowFacet());
    _facetAddresses.adminFacet = address(new AdminFacet());
    _facetAddresses.liquidationFacet = address(new LiquidationFacet());
    _facetAddresses.ownershipFacet = address(new OwnershipFacet());
  }

  function diamondCutAllMoneyMarketFacets(address _moneyMarketDiamond, FacetAddresses memory _facetAddresses) internal {
    // prepare selectors
    bytes4[] memory _diamondLoupeFacetSelectors = getDiamondLoupeFacetSelectors();
    bytes4[] memory _viewFacetSelectors = getViewFacetSelectors();
    bytes4[] memory _lendFacetSelectors = getLendFacetSelectors();
    bytes4[] memory _collateralFacetSelectors = getCollateralFacetSelectors();
    bytes4[] memory _borrowFacetSelectors = getBorrowFacetSelectors();
    bytes4[] memory _nonCollatBorrowFacetSelectors = getNonCollatBorrowFacetSelectors();
    bytes4[] memory _adminFacetSelectors = getAdminFacetSelectors();
    bytes4[] memory _liquidationFacetSelectors = getLiquidationFacetSelectors();
    bytes4[] memory _ownershipFacetSelectors = getOwnershipFacetSelectors();

    // prepare FacetCuts
    IDiamondCut.FacetCut[] memory _facetCuts = new IDiamondCut.FacetCut[](9);
    _facetCuts[0] = IDiamondCut.FacetCut({
      action: IDiamondCut.FacetCutAction.Add,
      facetAddress: _facetAddresses.diamondLoupeFacet,
      functionSelectors: _diamondLoupeFacetSelectors
    });
    _facetCuts[1] = IDiamondCut.FacetCut({
      action: IDiamondCut.FacetCutAction.Add,
      facetAddress: _facetAddresses.viewFacet,
      functionSelectors: _viewFacetSelectors
    });
    _facetCuts[2] = IDiamondCut.FacetCut({
      action: IDiamondCut.FacetCutAction.Add,
      facetAddress: _facetAddresses.lendFacet,
      functionSelectors: _lendFacetSelectors
    });
    _facetCuts[3] = IDiamondCut.FacetCut({
      action: IDiamondCut.FacetCutAction.Add,
      facetAddress: _facetAddresses.collateralFacet,
      functionSelectors: _collateralFacetSelectors
    });
    _facetCuts[4] = IDiamondCut.FacetCut({
      action: IDiamondCut.FacetCutAction.Add,
      facetAddress: _facetAddresses.borrowFacet,
      functionSelectors: _borrowFacetSelectors
    });
    _facetCuts[5] = IDiamondCut.FacetCut({
      action: IDiamondCut.FacetCutAction.Add,
      facetAddress: _facetAddresses.nonCollatBorrowFacet,
      functionSelectors: _nonCollatBorrowFacetSelectors
    });
    _facetCuts[6] = IDiamondCut.FacetCut({
      action: IDiamondCut.FacetCutAction.Add,
      facetAddress: _facetAddresses.adminFacet,
      functionSelectors: _adminFacetSelectors
    });
    _facetCuts[7] = IDiamondCut.FacetCut({
      action: IDiamondCut.FacetCutAction.Add,
      facetAddress: _facetAddresses.liquidationFacet,
      functionSelectors: _liquidationFacetSelectors
    });
    _facetCuts[8] = IDiamondCut.FacetCut({
      action: IDiamondCut.FacetCutAction.Add,
      facetAddress: _facetAddresses.ownershipFacet,
      functionSelectors: _ownershipFacetSelectors
    });

    // perform diamond cut on deployed MoneyMarketDiamond
    // address(0) and empty string means no initialization / cleanup after diamond cut
    DiamondCutFacet(_moneyMarketDiamond).diamondCut(_facetCuts, address(0), "");
  }

  function getDiamondLoupeFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](4);
    _selectors[0] = DiamondLoupeFacet.facets.selector;
    _selectors[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
    _selectors[2] = DiamondLoupeFacet.facetAddresses.selector;
    _selectors[3] = DiamondLoupeFacet.facetAddress.selector;
  }

  function getViewFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](39);
    _selectors[0] = ViewFacet.getProtocolReserve.selector;
    _selectors[1] = ViewFacet.getTokenConfig.selector;
    _selectors[2] = ViewFacet.getOverCollatDebtSharesOf.selector;
    _selectors[3] = ViewFacet.getTotalBorrowingPower.selector;
    _selectors[4] = ViewFacet.getTotalUsedBorrowingPower.selector;
    _selectors[5] = ViewFacet.getOverCollatTokenDebt.selector;
    _selectors[6] = ViewFacet.getDebtLastAccruedAt.selector;
    _selectors[7] = ViewFacet.getGlobalPendingInterest.selector;
    _selectors[8] = ViewFacet.getOverCollatTokenDebtValue.selector;
    _selectors[9] = ViewFacet.getOverCollatTokenDebtShares.selector;
    _selectors[10] = ViewFacet.getFloatingBalance.selector;
    _selectors[11] = ViewFacet.getOverCollatDebtShareAndAmountOf.selector;
    _selectors[12] = ViewFacet.getAllSubAccountCollats.selector;
    _selectors[13] = ViewFacet.getTotalCollat.selector;
    _selectors[14] = ViewFacet.getCollatAmountOf.selector;
    _selectors[15] = ViewFacet.getTotalToken.selector;
    _selectors[16] = ViewFacet.getRepurchaseRewardModel.selector;
    _selectors[17] = ViewFacet.getTotalTokenWithPendingInterest.selector;
    _selectors[18] = ViewFacet.getNonCollatAccountDebtValues.selector;
    _selectors[19] = ViewFacet.getNonCollatAccountDebt.selector;
    _selectors[20] = ViewFacet.getNonCollatTokenDebt.selector;
    _selectors[21] = ViewFacet.getNonCollatBorrowingPower.selector;
    _selectors[22] = ViewFacet.getIbTokenFromToken.selector;
    _selectors[23] = ViewFacet.getTokenFromIbToken.selector;
    _selectors[24] = ViewFacet.getTotalNonCollatUsedBorrowingPower.selector;
    _selectors[25] = ViewFacet.getLiquidationParams.selector;
    _selectors[26] = ViewFacet.getMaxNumOfToken.selector;
    _selectors[27] = ViewFacet.getGlobalDebtValue.selector;
    _selectors[28] = ViewFacet.getMinDebtSize.selector;
    _selectors[29] = ViewFacet.getSubAccount.selector;
    _selectors[30] = ViewFacet.getFeeParams.selector;
    _selectors[31] = ViewFacet.getGlobalDebtValueWithPendingInterest.selector;
    _selectors[32] = ViewFacet.getIbTokenImplementation.selector;
    _selectors[33] = ViewFacet.getLiquidationTreasury.selector;
    _selectors[34] = ViewFacet.getDebtTokenFromToken.selector;
    _selectors[35] = ViewFacet.getDebtTokenImplementation.selector;
    _selectors[36] = ViewFacet.getMiniFLPoolIdOfToken.selector;
    _selectors[37] = ViewFacet.getOracle.selector;
    _selectors[38] = ViewFacet.getMiniFL.selector;
  }

  function getLendFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](2);
    _selectors[0] = LendFacet.deposit.selector;
    _selectors[1] = LendFacet.withdraw.selector;
  }

  function getCollateralFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](3);
    _selectors[0] = CollateralFacet.addCollateral.selector;
    _selectors[1] = CollateralFacet.removeCollateral.selector;
    _selectors[2] = CollateralFacet.transferCollateral.selector;
  }

  function getBorrowFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](4);
    _selectors[0] = BorrowFacet.borrow.selector;
    _selectors[1] = BorrowFacet.repay.selector;
    _selectors[2] = BorrowFacet.accrueInterest.selector;
    _selectors[3] = BorrowFacet.repayWithCollat.selector;
  }

  function getNonCollatBorrowFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](2);
    _selectors[0] = NonCollatBorrowFacet.nonCollatBorrow.selector;
    _selectors[1] = NonCollatBorrowFacet.nonCollatRepay.selector;
  }

  function getAdminFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](23);
    _selectors[0] = AdminFacet.openMarket.selector;
    _selectors[1] = AdminFacet.setTokenConfigs.selector;
    _selectors[2] = AdminFacet.setNonCollatBorrowerOk.selector;
    _selectors[3] = AdminFacet.setInterestModel.selector;
    _selectors[4] = AdminFacet.setOracle.selector;
    _selectors[5] = AdminFacet.setRepurchasersOk.selector;
    _selectors[6] = AdminFacet.setNonCollatInterestModel.selector;
    _selectors[7] = AdminFacet.setLiquidationStratsOk.selector;
    _selectors[8] = AdminFacet.setLiquidatorsOk.selector;
    _selectors[9] = AdminFacet.setLiquidationTreasury.selector;
    _selectors[10] = AdminFacet.setFees.selector;
    _selectors[11] = AdminFacet.withdrawProtocolReserve.selector;
    _selectors[12] = AdminFacet.setProtocolConfigs.selector;
    _selectors[13] = AdminFacet.setIbTokenImplementation.selector;
    _selectors[14] = AdminFacet.setLiquidationParams.selector;
    _selectors[15] = AdminFacet.setMaxNumOfToken.selector;
    _selectors[16] = AdminFacet.setMinDebtSize.selector;
    _selectors[17] = AdminFacet.writeOffSubAccountsDebt.selector;
    _selectors[18] = AdminFacet.topUpTokenReserve.selector;
    _selectors[19] = AdminFacet.setRepurchaseRewardModel.selector;
    _selectors[20] = AdminFacet.setEmergencyPaused.selector;
    _selectors[21] = AdminFacet.setAccountManagersOk.selector;
    _selectors[22] = AdminFacet.setDebtTokenImplementation.selector;
  }

  function getLiquidationFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](2);
    _selectors[0] = LiquidationFacet.repurchase.selector;
    _selectors[1] = LiquidationFacet.liquidationCall.selector;
  }

  function getOwnershipFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](4);
    _selectors[0] = OwnershipFacet.transferOwnership.selector;
    _selectors[1] = OwnershipFacet.acceptOwnership.selector;
    _selectors[2] = OwnershipFacet.owner.selector;
    _selectors[3] = OwnershipFacet.pendingOwner.selector;
  }
}
