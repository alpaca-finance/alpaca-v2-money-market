// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// utils
import { VM } from "solidity/tests/utils/VM.sol";

// core
import { LYFDiamond } from "../../contracts/lyf/LYFDiamond.sol";

// facets
import { LYFDiamondCutFacet, ILYFDiamondCut } from "../../contracts/lyf/facets/LYFDiamondCutFacet.sol";
import { LYFDiamondLoupeFacet } from "../../contracts/lyf/facets/LYFDiamondLoupeFacet.sol";
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
  VM internal constant vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

  struct FacetAddresses {
    address diamondCutFacet;
    address diamondLoupeFacet;
    address viewFacet;
    address collateralFacet;
    address farmFacet;
    address adminFacet;
    address liquidationFacet;
    address ownershipFacet;
  }

  function deployLYFDiamond(address _moneyMarketDiamond)
    internal
    returns (address _lyfDiamond, FacetAddresses memory _facetAddresses)
  {
    // deploy facets
    _facetAddresses = deployLYFFacets();

    // deploy LYFDiamond
    bytes memory _logicBytecode = abi.encodePacked(
      vm.getCode("./out/LYFDiamond.sol/LYFDiamond.json"),
      abi.encode(_facetAddresses.diamondCutFacet, _moneyMarketDiamond)
    );

    assembly {
      _lyfDiamond := create(0, add(_logicBytecode, 0x20), mload(_logicBytecode))
      if iszero(extcodesize(_lyfDiamond)) {
        revert(0, 0)
      }
    }

    // do diamondCut
    diamondCutAllLYFFacets(_lyfDiamond, _facetAddresses);

    return (_lyfDiamond, _facetAddresses);
  }

  function diamondCutAllLYFFacets(address _lyf, FacetAddresses memory _facetAddresses) internal {
    // prepare _selectors
    bytes4[] memory _diamondLoupeFacetSelectors = getLYFDiamondLoupeFacetSelectors();
    bytes4[] memory _viewFacetSelectors = getLYFViewFacetSelectors();
    bytes4[] memory _collateralFacetSelectors = getLYFCollateralFacetSelectors();
    bytes4[] memory _farmFacetSelectors = getLYFFarmFacetSelectors();
    bytes4[] memory _adminFacetSelectors = getLYFAdminFacetSelectors();
    bytes4[] memory _liquidationFacetSelectors = getLYFLiquidationFacetSelectors();
    bytes4[] memory _ownershipFacetSelectors = getLYFOwnershipFacetSelectors();

    // prepare FacetCuts
    ILYFDiamondCut.FacetCut[] memory _facetCuts = new ILYFDiamondCut.FacetCut[](7);
    _facetCuts[0] = ILYFDiamondCut.FacetCut({
      action: ILYFDiamondCut.FacetCutAction.Add,
      facetAddress: _facetAddresses.diamondLoupeFacet,
      functionSelectors: _diamondLoupeFacetSelectors
    });
    _facetCuts[1] = ILYFDiamondCut.FacetCut({
      action: ILYFDiamondCut.FacetCutAction.Add,
      facetAddress: _facetAddresses.viewFacet,
      functionSelectors: _viewFacetSelectors
    });
    _facetCuts[2] = ILYFDiamondCut.FacetCut({
      action: ILYFDiamondCut.FacetCutAction.Add,
      facetAddress: _facetAddresses.collateralFacet,
      functionSelectors: _collateralFacetSelectors
    });
    _facetCuts[3] = ILYFDiamondCut.FacetCut({
      action: ILYFDiamondCut.FacetCutAction.Add,
      facetAddress: _facetAddresses.farmFacet,
      functionSelectors: _farmFacetSelectors
    });
    _facetCuts[4] = ILYFDiamondCut.FacetCut({
      action: ILYFDiamondCut.FacetCutAction.Add,
      facetAddress: _facetAddresses.adminFacet,
      functionSelectors: _adminFacetSelectors
    });
    _facetCuts[5] = ILYFDiamondCut.FacetCut({
      action: ILYFDiamondCut.FacetCutAction.Add,
      facetAddress: _facetAddresses.liquidationFacet,
      functionSelectors: _liquidationFacetSelectors
    });
    _facetCuts[6] = ILYFDiamondCut.FacetCut({
      action: ILYFDiamondCut.FacetCutAction.Add,
      facetAddress: _facetAddresses.ownershipFacet,
      functionSelectors: _ownershipFacetSelectors
    });

    // perform diamond cut on deployed MoneyMarketDiamond
    // address(0) and empty string means no initialization / cleanup after diamond cut
    ILYFDiamondCut(_lyf).diamondCut(_facetCuts, address(0), "");
  }

  function deployLYFFacets() internal returns (FacetAddresses memory _facetAddresses) {
    _facetAddresses.diamondCutFacet = deployContract("./out/LYFDiamondCutFacet.sol/LYFDiamondCutFacet.json");
    _facetAddresses.diamondLoupeFacet = deployContract("./out/LYFDiamondLoupeFacet.sol/LYFDiamondLoupeFacet.json");
    _facetAddresses.viewFacet = deployContract("./out/LYFViewFacet.sol/LYFViewFacet.json");
    _facetAddresses.collateralFacet = deployContract("./out/LYFCollateralFacet.sol/LYFCollateralFacet.json");
    _facetAddresses.farmFacet = deployContract("./out/LYFFarmFacet.sol/LYFFarmFacet.json");
    _facetAddresses.adminFacet = deployContract("./out/LYFAdminFacet.sol/LYFAdminFacet.json");
    _facetAddresses.liquidationFacet = deployContract("./out/LYFLiquidationFacet.sol/LYFLiquidationFacet.json");
    _facetAddresses.ownershipFacet = deployContract("./out/LYFOwnershipFacet.sol/LYFOwnershipFacet.json");
  }

  function getLYFDiamondLoupeFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](4);
    _selectors[0] = LYFDiamondLoupeFacet.facets.selector;
    _selectors[1] = LYFDiamondLoupeFacet.facetFunctionSelectors.selector;
    _selectors[2] = LYFDiamondLoupeFacet.facetAddresses.selector;
    _selectors[3] = LYFDiamondLoupeFacet.facetAddress.selector;
  }

  function getLYFFarmFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](6);
    _selectors[0] = LYFFarmFacet.addFarmPosition.selector;
    _selectors[1] = LYFFarmFacet.repay.selector;
    _selectors[2] = LYFFarmFacet.accrueInterest.selector;
    _selectors[3] = LYFFarmFacet.reducePosition.selector;
    _selectors[4] = LYFFarmFacet.repayWithCollat.selector;
    _selectors[5] = LYFFarmFacet.reinvest.selector;
  }

  function getLYFAdminFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](17);
    _selectors[0] = LYFAdminFacet.setOracle.selector;
    _selectors[1] = LYFAdminFacet.setLiquidationTreasury.selector;
    _selectors[2] = LYFAdminFacet.setTokenConfigs.selector;
    _selectors[3] = LYFAdminFacet.setLPConfigs.selector;
    _selectors[4] = LYFAdminFacet.setDebtPoolId.selector;
    _selectors[5] = LYFAdminFacet.setDebtPoolInterestModel.selector;
    _selectors[6] = LYFAdminFacet.setReinvestorsOk.selector;
    _selectors[7] = LYFAdminFacet.setLiquidationStratsOk.selector;
    _selectors[8] = LYFAdminFacet.setLiquidatorsOk.selector;
    _selectors[9] = LYFAdminFacet.setMaxNumOfToken.selector;
    _selectors[10] = LYFAdminFacet.setMinDebtSize.selector;
    _selectors[11] = LYFAdminFacet.withdrawProtocolReserve.selector;
    _selectors[12] = LYFAdminFacet.setRevenueTreasury.selector;
    _selectors[13] = LYFAdminFacet.setRewardConversionConfigs.selector;
    _selectors[14] = LYFAdminFacet.settleDebt.selector;
    _selectors[15] = LYFAdminFacet.topUpTokenReserve.selector;
    _selectors[16] = LYFAdminFacet.writeOffSubAccountsDebt.selector;
  }

  function getLYFCollateralFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](3);
    _selectors[0] = LYFCollateralFacet.addCollateral.selector;
    _selectors[1] = LYFCollateralFacet.removeCollateral.selector;
    _selectors[2] = LYFCollateralFacet.transferCollateral.selector;
  }

  function getLYFLiquidationFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](3);
    _selectors[0] = LYFLiquidationFacet.repurchase.selector;
    _selectors[1] = LYFLiquidationFacet.lpLiquidationCall.selector;
    _selectors[2] = LYFLiquidationFacet.liquidationCall.selector;
  }

  function getLYFOwnershipFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](4);
    _selectors[0] = LYFOwnershipFacet.transferOwnership.selector;
    _selectors[1] = LYFOwnershipFacet.acceptOwnership.selector;
    _selectors[2] = LYFOwnershipFacet.owner.selector;
    _selectors[3] = LYFOwnershipFacet.pendingOwner.selector;
  }

  function getLYFViewFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](25);
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
    _selectors[24] = LYFViewFacet.getRewardConversionConfig.selector;
  }

  function deployContract(string memory _path) internal returns (address _deployedAddress) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode(_path));

    assembly {
      _deployedAddress := create(0, add(_logicBytecode, 0x20), mload(_logicBytecode))
      if iszero(extcodesize(_deployedAddress)) {
        revert(0, 0)
      }
    }
  }
}
