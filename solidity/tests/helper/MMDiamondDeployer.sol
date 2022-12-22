// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// core
import { MoneyMarketDiamond } from "../../contracts/money-market/MoneyMarketDiamond.sol";

// facets
import { DiamondCutFacet, IDiamondCut } from "../../contracts/money-market/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "../../contracts/money-market/facets/DiamondLoupeFacet.sol";
import { ViewFacet } from "../../contracts/money-market/facets/ViewFacet.sol";
import { LendFacet } from "../../contracts/money-market/facets/LendFacet.sol";
import { CollateralFacet } from "../../contracts/money-market/facets/CollateralFacet.sol";
import { BorrowFacet } from "../../contracts/money-market/facets/BorrowFacet.sol";
import { NonCollatBorrowFacet } from "../../contracts/money-market/facets/NonCollatBorrowFacet.sol";
import { AdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";
import { LiquidationFacet } from "../../contracts/money-market/facets/LiquidationFacet.sol";
import { OwnershipFacet } from "../../contracts/money-market/facets/OwnershipFacet.sol";

// initializers
import { DiamondInit } from "../../contracts/money-market/initializers/DiamondInit.sol";
import { MoneyMarketInit } from "../../contracts/money-market/initializers/MoneyMarketInit.sol";

library MMDiamondDeployer {
  function deployPoolDiamond(address _nativeToken, address _nativeRelayer) internal returns (address) {
    // Deploy DimondCutFacet
    DiamondCutFacet diamondCutFacet = new DiamondCutFacet();

    // Deploy Money Market
    MoneyMarketDiamond _moneyMarketDiamond = new MoneyMarketDiamond(address(this), address(diamondCutFacet));

    deployDiamondLoupeFacet(DiamondCutFacet(address(_moneyMarketDiamond)));
    deployLendFacet(DiamondCutFacet(address(_moneyMarketDiamond)));
    deployCollateralFacet(DiamondCutFacet(address(_moneyMarketDiamond)));
    deployBorrowFacet(DiamondCutFacet(address(_moneyMarketDiamond)));
    deployNonCollatBorrowFacet(DiamondCutFacet(address(_moneyMarketDiamond)));
    deployAdminFacet(DiamondCutFacet(address(_moneyMarketDiamond)));
    deployLiquidationFacet(DiamondCutFacet(address(_moneyMarketDiamond)));
    deployOwnershipFacet(DiamondCutFacet(address(_moneyMarketDiamond)));
    deployViewFacet(DiamondCutFacet(address(_moneyMarketDiamond)));

    initializeDiamond(DiamondCutFacet(address(_moneyMarketDiamond)));
    initializeMoneyMarket(DiamondCutFacet(address(_moneyMarketDiamond)), _nativeToken, _nativeRelayer);

    return (address(_moneyMarketDiamond));
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

  function initializeMoneyMarket(
    DiamondCutFacet diamondCutFacet,
    address _nativeToken,
    address _nativeRelayer
  ) internal {
    // Deploy DiamondInit
    MoneyMarketInit _initializer = new MoneyMarketInit();
    IDiamondCut.FacetCut[] memory facetCuts = new IDiamondCut.FacetCut[](0);

    // make lib diamond call init
    diamondCutFacet.diamondCut(
      facetCuts,
      address(_initializer),
      abi.encodeWithSelector(bytes4(keccak256("init(address,address)")), _nativeToken, _nativeRelayer)
    );
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

  function deployViewFacet(DiamondCutFacet diamondCutFacet) internal returns (ViewFacet, bytes4[] memory) {
    ViewFacet _viewFacet = new ViewFacet();

    bytes4[] memory selectors = new bytes4[](23);
    selectors[0] = ViewFacet.getProtocolReserve.selector;
    selectors[1] = ViewFacet.getTokenConfig.selector;
    selectors[2] = ViewFacet.getOverCollatDebtSharesOfSubAccount.selector;
    selectors[3] = ViewFacet.getTotalBorrowingPower.selector;
    selectors[4] = ViewFacet.getTotalUsedBorrowingPower.selector;
    selectors[5] = ViewFacet.getGlobalDebt.selector;
    selectors[6] = ViewFacet.getDebtLastAccrueTime.selector;
    selectors[7] = ViewFacet.pendingInterest.selector;
    selectors[8] = ViewFacet.debtValues.selector;
    selectors[9] = ViewFacet.getOverCollatDebtSharesOfToken.selector;
    selectors[10] = ViewFacet.getFloatingBalance.selector;
    selectors[11] = ViewFacet.getOverCollatSubAccountDebt.selector;
    selectors[12] = ViewFacet.getAllSubAccountCollats.selector;
    selectors[13] = ViewFacet.collats.selector;
    selectors[14] = ViewFacet.subAccountCollatAmount.selector;
    selectors[15] = ViewFacet.getTotalToken.selector;
    selectors[16] = ViewFacet.getIbShareFromUnderlyingAmount.selector;
    selectors[17] = ViewFacet.getTotalTokenWithPendingInterest.selector;
    selectors[18] = ViewFacet.nonCollatGetDebtValues.selector;
    selectors[19] = ViewFacet.nonCollatGetTotalUsedBorrowingPower.selector;
    selectors[20] = ViewFacet.nonCollatGetDebt.selector;
    selectors[21] = ViewFacet.nonCollatGetTokenDebt.selector;
    selectors[22] = ViewFacet.nonCollatBorrowLimitUSDValues.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_viewFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_viewFacet, selectors);
  }

  function deployLendFacet(DiamondCutFacet diamondCutFacet) internal returns (LendFacet, bytes4[] memory) {
    LendFacet _lendFacet = new LendFacet();

    bytes4[] memory selectors = new bytes4[](5);
    selectors[0] = LendFacet.deposit.selector;
    selectors[1] = LendFacet.withdraw.selector;
    selectors[2] = LendFacet.openMarket.selector;
    selectors[3] = LendFacet.depositETH.selector;
    selectors[4] = LendFacet.withdrawETH.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_lendFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_lendFacet, selectors);
  }

  function deployCollateralFacet(DiamondCutFacet diamondCutFacet) internal returns (CollateralFacet, bytes4[] memory) {
    CollateralFacet _collateralFacet = new CollateralFacet();

    bytes4[] memory selectors = new bytes4[](3);
    selectors[0] = CollateralFacet.addCollateral.selector;
    selectors[1] = CollateralFacet.removeCollateral.selector;
    selectors[2] = CollateralFacet.transferCollateral.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_collateralFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_collateralFacet, selectors);
  }

  function deployBorrowFacet(DiamondCutFacet diamondCutFacet) internal returns (BorrowFacet, bytes4[] memory) {
    BorrowFacet _brrowFacet = new BorrowFacet();

    bytes4[] memory selectors = new bytes4[](4);
    selectors[0] = BorrowFacet.borrow.selector;
    selectors[1] = BorrowFacet.repay.selector;
    selectors[2] = BorrowFacet.accrueInterest.selector;
    selectors[3] = BorrowFacet.repayWithCollat.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_brrowFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_brrowFacet, selectors);
  }

  function deployNonCollatBorrowFacet(DiamondCutFacet diamondCutFacet)
    internal
    returns (NonCollatBorrowFacet, bytes4[] memory)
  {
    NonCollatBorrowFacet _nonCollatBorrow = new NonCollatBorrowFacet();

    bytes4[] memory selectors = new bytes4[](2);
    selectors[0] = NonCollatBorrowFacet.nonCollatBorrow.selector;
    selectors[1] = NonCollatBorrowFacet.nonCollatRepay.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_nonCollatBorrow),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_nonCollatBorrow, selectors);
  }

  function deployAdminFacet(DiamondCutFacet diamondCutFacet) internal returns (AdminFacet, bytes4[] memory) {
    AdminFacet _adminFacet = new AdminFacet();

    bytes4[] memory selectors = new bytes4[](16);
    selectors[0] = AdminFacet.setTokenToIbTokens.selector;
    selectors[1] = AdminFacet.tokenToIbTokens.selector;
    selectors[2] = AdminFacet.ibTokenToTokens.selector;
    selectors[3] = AdminFacet.setTokenConfigs.selector;
    selectors[4] = AdminFacet.setNonCollatBorrower.selector;
    selectors[5] = AdminFacet.setInterestModel.selector;
    selectors[6] = AdminFacet.setOracle.selector;
    selectors[7] = AdminFacet.setRepurchasersOk.selector;
    selectors[8] = AdminFacet.setNonCollatInterestModel.selector;
    selectors[9] = AdminFacet.setLiquidationStratsOk.selector;
    selectors[10] = AdminFacet.setLiquidationCallersOk.selector;
    selectors[11] = AdminFacet.setTreasury.selector;
    selectors[12] = AdminFacet.setFees.selector;
    selectors[13] = AdminFacet.withdrawReserve.selector;
    selectors[14] = AdminFacet.setProtocolConfigs.selector;
    selectors[15] = AdminFacet.setIbTokenImplementation.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_adminFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_adminFacet, selectors);
  }

  function deployLiquidationFacet(DiamondCutFacet diamondCutFacet)
    internal
    returns (LiquidationFacet, bytes4[] memory)
  {
    LiquidationFacet _LiquidationFacet = new LiquidationFacet();

    bytes4[] memory selectors = new bytes4[](2);
    selectors[0] = _LiquidationFacet.repurchase.selector;
    selectors[1] = _LiquidationFacet.liquidationCall.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_LiquidationFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_LiquidationFacet, selectors);
  }

  function deployOwnershipFacet(DiamondCutFacet diamondCutFacet) internal returns (OwnershipFacet, bytes4[] memory) {
    OwnershipFacet _ownershipFacet = new OwnershipFacet();

    bytes4[] memory selectors = new bytes4[](4);
    selectors[0] = _ownershipFacet.transferOwnership.selector;
    selectors[1] = _ownershipFacet.acceptOwnership.selector;
    selectors[2] = _ownershipFacet.owner.selector;
    selectors[3] = _ownershipFacet.pendingOwner.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_ownershipFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_ownershipFacet, selectors);
  }
}
