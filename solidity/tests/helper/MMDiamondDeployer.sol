// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// core
import { MoneyMarketDiamond } from "../../contracts/money-market/MoneyMarketDiamond.sol";

// facets
import { DiamondCutFacet, IDiamondCut } from "../../contracts/money-market/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "../../contracts/money-market/facets/DiamondLoupeFacet.sol";
import { LendFacet } from "../../contracts/money-market/facets/LendFacet.sol";
import { CollateralFacet } from "../../contracts/money-market/facets/CollateralFacet.sol";
import { BorrowFacet } from "../../contracts/money-market/facets/BorrowFacet.sol";
import { NonCollatBorrowFacet } from "../../contracts/money-market/facets/NonCollatBorrowFacet.sol";
import { AdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";
import { LiquidationFacet } from "../../contracts/money-market/facets/LiquidationFacet.sol";

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

  function deployLendFacet(DiamondCutFacet diamondCutFacet) internal returns (LendFacet, bytes4[] memory) {
    LendFacet _lendFacet = new LendFacet();

    bytes4[] memory selectors = new bytes4[](8);
    selectors[0] = LendFacet.deposit.selector;
    selectors[1] = LendFacet.withdraw.selector;
    selectors[2] = LendFacet.getTotalToken.selector;
    selectors[3] = LendFacet.openMarket.selector;
    selectors[4] = LendFacet.depositETH.selector;
    selectors[5] = LendFacet.withdrawETH.selector;
    selectors[6] = LendFacet.getIbShareFromUnderlyingAmount.selector;
    selectors[7] = LendFacet.getTotalTokenWithPendingInterest.selector;

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

    bytes4[] memory selectors = new bytes4[](6);
    selectors[0] = CollateralFacet.addCollateral.selector;
    selectors[1] = CollateralFacet.getCollaterals.selector;
    selectors[2] = CollateralFacet.removeCollateral.selector;
    selectors[3] = CollateralFacet.collats.selector;
    selectors[4] = CollateralFacet.transferCollateral.selector;
    selectors[5] = CollateralFacet.subAccountCollatAmount.selector;

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

    bytes4[] memory selectors = new bytes4[](14);
    selectors[0] = BorrowFacet.borrow.selector;
    selectors[1] = BorrowFacet.getDebtShares.selector;
    selectors[2] = BorrowFacet.getTotalBorrowingPower.selector;
    selectors[3] = BorrowFacet.getTotalUsedBorrowingPower.selector;
    selectors[4] = BorrowFacet.getDebt.selector;
    selectors[5] = BorrowFacet.repay.selector;
    selectors[6] = BorrowFacet.getGlobalDebt.selector;
    selectors[7] = BorrowFacet.debtLastAccrueTime.selector;
    selectors[8] = BorrowFacet.pendingInterest.selector;
    selectors[9] = BorrowFacet.accrueInterest.selector;
    selectors[10] = BorrowFacet.debtValues.selector;
    selectors[11] = BorrowFacet.debtShares.selector;
    selectors[12] = BorrowFacet.repayWithCollat.selector;
    selectors[13] = BorrowFacet.getFloatingBalance.selector;

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

    bytes4[] memory selectors = new bytes4[](7);
    selectors[0] = NonCollatBorrowFacet.nonCollatBorrow.selector;
    selectors[1] = NonCollatBorrowFacet.nonCollatGetDebtValues.selector;
    selectors[2] = NonCollatBorrowFacet.nonCollatGetTotalUsedBorrowingPower.selector;
    selectors[3] = NonCollatBorrowFacet.nonCollatGetDebt.selector;
    selectors[4] = NonCollatBorrowFacet.nonCollatRepay.selector;
    selectors[5] = NonCollatBorrowFacet.nonCollatGetTokenDebt.selector;
    selectors[6] = NonCollatBorrowFacet.nonCollatBorrowLimitUSDValues.selector;

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

    bytes4[] memory selectors = new bytes4[](19);
    selectors[0] = AdminFacet.setTokenToIbTokens.selector;
    selectors[1] = AdminFacet.tokenToIbTokens.selector;
    selectors[2] = AdminFacet.ibTokenToTokens.selector;
    selectors[3] = AdminFacet.setTokenConfigs.selector;
    selectors[4] = AdminFacet.tokenConfigs.selector;
    selectors[5] = AdminFacet.setNonCollatBorrower.selector;
    selectors[6] = AdminFacet.setInterestModel.selector;
    selectors[7] = AdminFacet.setOracle.selector;
    selectors[8] = AdminFacet.setRepurchasersOk.selector;
    selectors[9] = AdminFacet.setNonCollatBorrowLimitUSDValues.selector;
    selectors[10] = AdminFacet.setNonCollatInterestModel.selector;
    selectors[11] = AdminFacet.setLiquidationStratsOk.selector;
    selectors[12] = AdminFacet.setLiquidationCallersOk.selector;
    selectors[14] = AdminFacet.setTreasury.selector;
    selectors[15] = AdminFacet.setFees.selector;
    selectors[16] = AdminFacet.getProtocolReserve.selector;
    selectors[17] = AdminFacet.withdrawReserve.selector;
    selectors[18] = AdminFacet.setIbTokenImplementation.selector;

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
}
