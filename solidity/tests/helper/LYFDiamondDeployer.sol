// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// utils
import { VM } from "solidity/tests/utils/VM.sol";

// facets
import { ILYFDiamondCut } from "../../contracts/lyf/interfaces/ILYFDiamondCut.sol";
import { LYFDiamondLoupeFacet } from "../../contracts/lyf/facets/LYFDiamondLoupeFacet.sol";
import { ILYFAdminFacet } from "../../contracts/lyf/interfaces/ILYFAdminFacet.sol";
import { ILYFCollateralFacet } from "../../contracts/lyf/interfaces/ILYFCollateralFacet.sol";
import { ILYFFarmFacet } from "../../contracts/lyf/interfaces/ILYFFarmFacet.sol";
import { ILYFLiquidationFacet } from "../../contracts/lyf/interfaces/ILYFLiquidationFacet.sol";
import { ILYFOwnershipFacet } from "../../contracts/lyf/interfaces/ILYFOwnershipFacet.sol";
import { ILYFViewFacet } from "../../contracts/lyf/interfaces/ILYFViewFacet.sol";

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

  function diamondCutAllLYFFacets(address _lyf, FacetAddresses memory _facetAddresses) internal {
    // prepare _selectors
    bytes4[] memory _diamondLoupeFacetSelectors = getLYFDiamondLoupeFacetSelectors();
    bytes4[] memory _viewFacetSelectors = getLYFViewFacetSelectors();
    bytes4[] memory _collateralFacetSelectors = getLYFCollateralFacetSelectors();
    bytes4[] memory _farmFacetSelectors = getLYFFarmFacetSelectors();
    bytes4[] memory _adminFacetSelectors = getILYFAdminFacetSelectors();
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

  function getLYFDiamondLoupeFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](4);
    _selectors[0] = LYFDiamondLoupeFacet.facets.selector;
    _selectors[1] = LYFDiamondLoupeFacet.facetFunctionSelectors.selector;
    _selectors[2] = LYFDiamondLoupeFacet.facetAddresses.selector;
    _selectors[3] = LYFDiamondLoupeFacet.facetAddress.selector;
  }

  function getLYFFarmFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](6);
    _selectors[0] = ILYFFarmFacet.addFarmPosition.selector;
    _selectors[1] = ILYFFarmFacet.repay.selector;
    _selectors[2] = ILYFFarmFacet.accrueInterest.selector;
    _selectors[3] = ILYFFarmFacet.reducePosition.selector;
    _selectors[4] = ILYFFarmFacet.repayWithCollat.selector;
    _selectors[5] = ILYFFarmFacet.reinvest.selector;
  }

  function getILYFAdminFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](17);
    _selectors[0] = ILYFAdminFacet.setOracle.selector;
    _selectors[1] = ILYFAdminFacet.setLiquidationTreasury.selector;
    _selectors[2] = ILYFAdminFacet.setTokenConfigs.selector;
    _selectors[3] = ILYFAdminFacet.setLPConfigs.selector;
    _selectors[4] = ILYFAdminFacet.setDebtPoolId.selector;
    _selectors[5] = ILYFAdminFacet.setDebtPoolInterestModel.selector;
    _selectors[6] = ILYFAdminFacet.setReinvestorsOk.selector;
    _selectors[7] = ILYFAdminFacet.setLiquidationStratsOk.selector;
    _selectors[8] = ILYFAdminFacet.setLiquidatorsOk.selector;
    _selectors[9] = ILYFAdminFacet.setMaxNumOfToken.selector;
    _selectors[10] = ILYFAdminFacet.setMinDebtSize.selector;
    _selectors[11] = ILYFAdminFacet.withdrawProtocolReserve.selector;
    _selectors[12] = ILYFAdminFacet.setRevenueTreasury.selector;
    _selectors[13] = ILYFAdminFacet.setRewardConversionConfigs.selector;
    _selectors[14] = ILYFAdminFacet.settleDebt.selector;
    _selectors[15] = ILYFAdminFacet.topUpTokenReserve.selector;
    _selectors[16] = ILYFAdminFacet.writeOffSubAccountsDebt.selector;
  }

  function getLYFCollateralFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](3);
    _selectors[0] = ILYFCollateralFacet.addCollateral.selector;
    _selectors[1] = ILYFCollateralFacet.removeCollateral.selector;
    _selectors[2] = ILYFCollateralFacet.transferCollateral.selector;
  }

  function getLYFLiquidationFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](3);
    _selectors[0] = ILYFLiquidationFacet.repurchase.selector;
    _selectors[1] = ILYFLiquidationFacet.lpLiquidationCall.selector;
    _selectors[2] = ILYFLiquidationFacet.liquidationCall.selector;
  }

  function getLYFOwnershipFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](4);
    _selectors[0] = ILYFOwnershipFacet.transferOwnership.selector;
    _selectors[1] = ILYFOwnershipFacet.acceptOwnership.selector;
    _selectors[2] = ILYFOwnershipFacet.owner.selector;
    _selectors[3] = ILYFOwnershipFacet.pendingOwner.selector;
  }

  function getLYFViewFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](25);
    _selectors[0] = ILYFViewFacet.getOracle.selector;
    _selectors[1] = ILYFViewFacet.getLpTokenConfig.selector;
    _selectors[2] = ILYFViewFacet.getLpTokenAmount.selector;
    _selectors[3] = ILYFViewFacet.getLpTokenShare.selector;
    _selectors[4] = ILYFViewFacet.getAllSubAccountCollats.selector;
    _selectors[5] = ILYFViewFacet.getTokenCollatAmount.selector;
    _selectors[6] = ILYFViewFacet.getSubAccountTokenCollatAmount.selector;
    _selectors[7] = ILYFViewFacet.getMMDebt.selector;
    _selectors[8] = ILYFViewFacet.getDebtPoolInfo.selector;
    _selectors[9] = ILYFViewFacet.getDebtPoolTotalValue.selector;
    _selectors[10] = ILYFViewFacet.getDebtPoolTotalShare.selector;
    _selectors[11] = ILYFViewFacet.getSubAccountDebt.selector;
    _selectors[12] = ILYFViewFacet.getAllSubAccountDebtShares.selector;
    _selectors[13] = ILYFViewFacet.getDebtPoolLastAccruedAt.selector;
    _selectors[14] = ILYFViewFacet.getDebtPoolPendingInterest.selector;
    _selectors[15] = ILYFViewFacet.getPendingReward.selector;
    _selectors[16] = ILYFViewFacet.getTotalBorrowingPower.selector;
    _selectors[17] = ILYFViewFacet.getTotalUsedBorrowingPower.selector;
    _selectors[18] = ILYFViewFacet.getMaxNumOfToken.selector;
    _selectors[19] = ILYFViewFacet.getMinDebtSize.selector;
    _selectors[20] = ILYFViewFacet.getOutstandingBalanceOf.selector;
    _selectors[21] = ILYFViewFacet.getProtocolReserveOf.selector;
    _selectors[22] = ILYFViewFacet.getSubAccount.selector;
    _selectors[23] = ILYFViewFacet.getDebtPoolIdOf.selector;
    _selectors[24] = ILYFViewFacet.getRewardConversionConfig.selector;
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
