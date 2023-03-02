// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// utils
import { VM } from "solidity/tests/utils/VM.sol";

// core
import { MoneyMarketDiamond } from "../../../contracts/money-market/MoneyMarketDiamond.sol";

// facets
import { DiamondCutFacet, IDiamondCut } from "../../../contracts/money-market/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "../../../contracts/money-market/facets/DiamondLoupeFacet.sol";
import { IViewFacet } from "../../../contracts/money-market/interfaces/IViewFacet.sol";
import { ILendFacet } from "../../../contracts/money-market/interfaces/ILendFacet.sol";
import { ICollateralFacet } from "../../../contracts/money-market/interfaces/ICollateralFacet.sol";
import { IBorrowFacet } from "../../../contracts/money-market/interfaces/IBorrowFacet.sol";
import { INonCollatBorrowFacet } from "../../../contracts/money-market/interfaces/INonCollatBorrowFacet.sol";
import { IAdminFacet } from "../../../contracts/money-market/interfaces/IAdminFacet.sol";
import { ILiquidationFacet } from "../../../contracts/money-market/interfaces/ILiquidationFacet.sol";
import { IOwnershipFacet } from "../../../contracts/money-market/interfaces/IOwnershipFacet.sol";

/// @dev Older version of deployment will always compile the contracts
// import { DiamondCutFacet, IDiamondCut } from "../../../contracts/money-market/facets/DiamondCutFacet.sol";
// import { DiamondLoupeFacet } from "../../../contracts/money-market/facets/DiamondLoupeFacet.sol";
// import { ViewFacet } from "../../../contracts/money-market/facets/ViewFacet.sol";
// import { LendFacet } from "../../../contracts/money-market/facets/LendFacet.sol";
// import { CollateralFacet } from "../../../contracts/money-market/facets/CollateralFacet.sol";
// import { BorrowFacet } from "../../../contracts/money-market/facets/BorrowFacet.sol";
// import { NonCollatBorrowFacet } from "../../../contracts/money-market/facets/NonCollatBorrowFacet.sol";
// import { AdminFacet } from "../../../contracts/money-market/facets/AdminFacet.sol";
// import { LiquidationFacet } from "../../../contracts/money-market/facets/LiquidationFacet.sol";
import { OwnershipFacet } from "../../../contracts/money-market/facets/OwnershipFacet.sol";

library LibMoneyMarketDeployment {
  VM internal constant vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
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
    _facetAddresses.diamondCutFacet = deployContract("./out/DiamondCutFacet.sol/DiamondCutFacet.json");
    _facetAddresses.diamondLoupeFacet = deployContract("./out/DiamondLoupeFacet.sol/DiamondLoupeFacet.json");
    _facetAddresses.viewFacet = deployContract("./out/ViewFacet.sol/ViewFacet.json");
    _facetAddresses.lendFacet = deployContract("./out/LendFacet.sol/LendFacet.json");
    _facetAddresses.collateralFacet = deployContract("./out/CollateralFacet.sol/CollateralFacet.json");
    _facetAddresses.borrowFacet = deployContract("./out/BorrowFacet.sol/BorrowFacet.json");
    _facetAddresses.nonCollatBorrowFacet = deployContract("./out/NonCollatBorrowFacet.sol/NonCollatBorrowFacet.json");
    _facetAddresses.adminFacet = deployContract("./out/AdminFacet.sol/AdminFacet.json");
    _facetAddresses.liquidationFacet = deployContract("./out/LiquidationFacet.sol/LiquidationFacet.json");
    // _facetAddresses.ownershipFacet = deployContract("./out/OwnershipFacet.sol/OwnershipFacet.json");

    /// @dev Older version of deployment approach
    // _facetAddresses.diamondCutFacet = address(new DiamondCutFacet());
    // _facetAddresses.diamondLoupeFacet = address(new DiamondLoupeFacet());
    // _facetAddresses.viewFacet = address(new ViewFacet());
    // _facetAddresses.lendFacet = address(new LendFacet());
    // _facetAddresses.collateralFacet = address(new CollateralFacet());
    // _facetAddresses.borrowFacet = address(new BorrowFacet());
    // _facetAddresses.nonCollatBorrowFacet = address(new NonCollatBorrowFacet());
    // _facetAddresses.adminFacet = address(new AdminFacet());
    // _facetAddresses.liquidationFacet = address(new LiquidationFacet());
    _facetAddresses.ownershipFacet = address(new OwnershipFacet());
  }

  function deployContract(string memory _path) internal returns (address _deployedAddress) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode(_path));

    assembly {
      _deployedAddress := create(0, add(_logicBytecode, 0x20), mload(_logicBytecode))
    }
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
    _selectors = new bytes4[](40);
    _selectors[0] = IViewFacet.getProtocolReserve.selector;
    _selectors[1] = IViewFacet.getTokenConfig.selector;
    _selectors[2] = IViewFacet.getOverCollatDebtSharesOf.selector;
    _selectors[3] = IViewFacet.getTotalBorrowingPower.selector;
    _selectors[4] = IViewFacet.getTotalUsedBorrowingPower.selector;
    _selectors[5] = IViewFacet.getOverCollatTokenDebt.selector;
    _selectors[6] = IViewFacet.getDebtLastAccruedAt.selector;
    _selectors[7] = IViewFacet.getGlobalPendingInterest.selector;
    _selectors[8] = IViewFacet.getOverCollatTokenDebtValue.selector;
    _selectors[9] = IViewFacet.getOverCollatTokenDebtShares.selector;
    _selectors[10] = IViewFacet.getFloatingBalance.selector;
    _selectors[11] = IViewFacet.getOverCollatDebtShareAndAmountOf.selector;
    _selectors[12] = IViewFacet.getAllSubAccountCollats.selector;
    _selectors[13] = IViewFacet.getTotalCollat.selector;
    _selectors[14] = IViewFacet.getCollatAmountOf.selector;
    _selectors[15] = IViewFacet.getTotalToken.selector;
    _selectors[16] = IViewFacet.getRepurchaseRewardModel.selector;
    _selectors[17] = IViewFacet.getTotalTokenWithPendingInterest.selector;
    _selectors[18] = IViewFacet.getNonCollatAccountDebtValues.selector;
    _selectors[19] = IViewFacet.getNonCollatAccountDebt.selector;
    _selectors[20] = IViewFacet.getNonCollatTokenDebt.selector;
    _selectors[21] = IViewFacet.getNonCollatBorrowingPower.selector;
    _selectors[22] = IViewFacet.getIbTokenFromToken.selector;
    _selectors[23] = IViewFacet.getTokenFromIbToken.selector;
    _selectors[24] = IViewFacet.getTotalNonCollatUsedBorrowingPower.selector;
    _selectors[25] = IViewFacet.getLiquidationParams.selector;
    _selectors[26] = IViewFacet.getMaxNumOfToken.selector;
    _selectors[27] = IViewFacet.getGlobalDebtValue.selector;
    _selectors[28] = IViewFacet.getMinDebtSize.selector;
    _selectors[29] = IViewFacet.getSubAccount.selector;
    _selectors[30] = IViewFacet.getFeeParams.selector;
    _selectors[31] = IViewFacet.getGlobalDebtValueWithPendingInterest.selector;
    _selectors[32] = IViewFacet.getIbTokenImplementation.selector;
    _selectors[33] = IViewFacet.getLiquidationTreasury.selector;
    _selectors[34] = IViewFacet.getDebtTokenFromToken.selector;
    _selectors[35] = IViewFacet.getDebtTokenImplementation.selector;
    _selectors[36] = IViewFacet.getMiniFLPoolIdOfToken.selector;
    _selectors[37] = IViewFacet.getOracle.selector;
    _selectors[38] = IViewFacet.getMiniFL.selector;
    _selectors[39] = IViewFacet.getOverCollatPendingInterest.selector;
  }

  function getLendFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](2);
    _selectors[0] = ILendFacet.deposit.selector;
    _selectors[1] = ILendFacet.withdraw.selector;
  }

  function getCollateralFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](3);
    _selectors[0] = ICollateralFacet.addCollateral.selector;
    _selectors[1] = ICollateralFacet.removeCollateral.selector;
    _selectors[2] = ICollateralFacet.transferCollateral.selector;
  }

  function getBorrowFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](4);
    _selectors[0] = IBorrowFacet.borrow.selector;
    _selectors[1] = IBorrowFacet.repay.selector;
    _selectors[2] = IBorrowFacet.accrueInterest.selector;
    _selectors[3] = IBorrowFacet.repayWithCollat.selector;
  }

  function getNonCollatBorrowFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](2);
    _selectors[0] = INonCollatBorrowFacet.nonCollatBorrow.selector;
    _selectors[1] = INonCollatBorrowFacet.nonCollatRepay.selector;
  }

  function getAdminFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](23);
    _selectors[0] = IAdminFacet.openMarket.selector;
    _selectors[1] = IAdminFacet.setTokenConfigs.selector;
    _selectors[2] = IAdminFacet.setNonCollatBorrowerOk.selector;
    _selectors[3] = IAdminFacet.setInterestModel.selector;
    _selectors[4] = IAdminFacet.setOracle.selector;
    _selectors[5] = IAdminFacet.setRepurchasersOk.selector;
    _selectors[6] = IAdminFacet.setNonCollatInterestModel.selector;
    _selectors[7] = IAdminFacet.setLiquidationStratsOk.selector;
    _selectors[8] = IAdminFacet.setLiquidatorsOk.selector;
    _selectors[9] = IAdminFacet.setLiquidationTreasury.selector;
    _selectors[10] = IAdminFacet.setFees.selector;
    _selectors[11] = IAdminFacet.withdrawProtocolReserve.selector;
    _selectors[12] = IAdminFacet.setProtocolConfigs.selector;
    _selectors[13] = IAdminFacet.setIbTokenImplementation.selector;
    _selectors[14] = IAdminFacet.setLiquidationParams.selector;
    _selectors[15] = IAdminFacet.setMaxNumOfToken.selector;
    _selectors[16] = IAdminFacet.setMinDebtSize.selector;
    _selectors[17] = IAdminFacet.writeOffSubAccountsDebt.selector;
    _selectors[18] = IAdminFacet.topUpTokenReserve.selector;
    _selectors[19] = IAdminFacet.setRepurchaseRewardModel.selector;
    _selectors[20] = IAdminFacet.setEmergencyPaused.selector;
    _selectors[21] = IAdminFacet.setAccountManagersOk.selector;
    _selectors[22] = IAdminFacet.setDebtTokenImplementation.selector;
  }

  function getLiquidationFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](2);
    _selectors[0] = ILiquidationFacet.repurchase.selector;
    _selectors[1] = ILiquidationFacet.liquidationCall.selector;
  }

  function getOwnershipFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](4);
    _selectors[0] = IOwnershipFacet.transferOwnership.selector;
    _selectors[1] = IOwnershipFacet.acceptOwnership.selector;
    _selectors[2] = IOwnershipFacet.owner.selector;
    _selectors[3] = IOwnershipFacet.pendingOwner.selector;
  }
}
