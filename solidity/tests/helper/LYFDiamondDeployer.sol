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

  function deployLYFDiamond(address _moneyMarket) internal returns (address) {
    // Deploy DimondCutFacet
    LYFDiamondCutFacet diamondCutFacet = new LYFDiamondCutFacet();

    // Deploy LYF
    LYFDiamond _lyfDiamond = new LYFDiamond(address(this), address(diamondCutFacet));

    deployAdminFacet(LYFDiamondCutFacet(address(_lyfDiamond)));
    deployLYFCollateralFacet(LYFDiamondCutFacet(address(_lyfDiamond)));
    deployFarmFacet(LYFDiamondCutFacet(address(_lyfDiamond)));
    deployLYFLiquidationFacet(LYFDiamondCutFacet(address(_lyfDiamond)));
    deployLYFOwnershipFacet(LYFDiamondCutFacet(address(_lyfDiamond)));
    deployLYFViewFacet(LYFDiamondCutFacet(address(_lyfDiamond)));

    initializeDiamond(LYFDiamondCutFacet(address(_lyfDiamond)));
    initializeLYF(LYFDiamondCutFacet(address(_lyfDiamond)), _moneyMarket);

    return (address(_lyfDiamond));
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

  function initializeDiamond(LYFDiamondCutFacet diamondCutFacet) internal {
    // Deploy DiamondInit
    DiamondInit diamondInitializer = new DiamondInit();
    ILYFDiamondCut.FacetCut[] memory facetCuts = new ILYFDiamondCut.FacetCut[](0);

    // make lib diamond call init
    diamondCutFacet.diamondCut(
      facetCuts,
      address(diamondInitializer),
      abi.encodeWithSelector(bytes4(keccak256("init()")))
    );
  }

  function initializeLYF(LYFDiamondCutFacet diamondCutFacet, address _moneyMarket) internal {
    // Deploy DiamondInit
    LYFInit _initializer = new LYFInit();
    ILYFDiamondCut.FacetCut[] memory facetCuts = new ILYFDiamondCut.FacetCut[](0);

    // make lib diamond call init
    diamondCutFacet.diamondCut(
      facetCuts,
      address(_initializer),
      abi.encodeWithSelector(bytes4(keccak256("init(address)")), _moneyMarket)
    );
  }

  function deployLYFDiamondLoupeFacet(LYFDiamondCutFacet diamondCutFacet)
    internal
    returns (LYFDiamondLoupeFacet, bytes4[] memory)
  {
    LYFDiamondLoupeFacet _diamondLoupeFacet = new LYFDiamondLoupeFacet();

    bytes4[] memory selectors = new bytes4[](4);
    selectors[0] = LYFDiamondLoupeFacet.facets.selector;
    selectors[1] = LYFDiamondLoupeFacet.facetFunctionSelectors.selector;
    selectors[2] = LYFDiamondLoupeFacet.facetAddresses.selector;
    selectors[3] = LYFDiamondLoupeFacet.facetAddress.selector;

    ILYFDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_diamondLoupeFacet),
      ILYFDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_diamondLoupeFacet, selectors);
  }

  function deployFarmFacet(LYFDiamondCutFacet diamondCutFacet) internal returns (LYFFarmFacet, bytes4[] memory) {
    LYFFarmFacet _farmFacet = new LYFFarmFacet();

    bytes4[] memory selectors = new bytes4[](6);
    selectors[0] = LYFFarmFacet.addFarmPosition.selector;
    selectors[1] = LYFFarmFacet.repay.selector;
    selectors[2] = LYFFarmFacet.accrueInterest.selector;
    selectors[3] = LYFFarmFacet.reducePosition.selector;
    selectors[4] = LYFFarmFacet.repayWithCollat.selector;
    selectors[5] = LYFFarmFacet.reinvest.selector;

    ILYFDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_farmFacet),
      ILYFDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_farmFacet, selectors);
  }

  function deployAdminFacet(LYFDiamondCutFacet diamondCutFacet) internal returns (LYFAdminFacet, bytes4[] memory) {
    LYFAdminFacet _adminFacet = new LYFAdminFacet();

    bytes4[] memory selectors = new bytes4[](17);
    selectors[0] = LYFAdminFacet.setOracle.selector;
    selectors[1] = LYFAdminFacet.setLiquidationTreasury.selector;
    selectors[2] = LYFAdminFacet.setTokenConfigs.selector;
    selectors[3] = LYFAdminFacet.setLPConfigs.selector;
    selectors[4] = LYFAdminFacet.setDebtPoolId.selector;
    selectors[5] = LYFAdminFacet.setDebtPoolInterestModel.selector;
    selectors[6] = LYFAdminFacet.setReinvestorsOk.selector;
    selectors[7] = LYFAdminFacet.setLiquidationStratsOk.selector;
    selectors[8] = LYFAdminFacet.setLiquidatorsOk.selector;
    selectors[9] = LYFAdminFacet.setMaxNumOfToken.selector;
    selectors[10] = LYFAdminFacet.setMinDebtSize.selector;
    selectors[11] = LYFAdminFacet.withdrawProtocolReserve.selector;
    selectors[12] = LYFAdminFacet.setRevenueTreasury.selector;
    selectors[13] = LYFAdminFacet.setRewardConversionConfigs.selector;
    selectors[14] = LYFAdminFacet.settleDebt.selector;
    selectors[15] = LYFAdminFacet.topUpTokenReserve.selector;
    selectors[16] = LYFAdminFacet.writeOffSubAccountsDebt.selector;
    ILYFDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_adminFacet),
      ILYFDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_adminFacet, selectors);
  }

  function deployLYFCollateralFacet(LYFDiamondCutFacet diamondCutFacet)
    internal
    returns (LYFCollateralFacet _collatFacet, bytes4[] memory _selectors)
  {
    _collatFacet = new LYFCollateralFacet();

    _selectors = new bytes4[](3);
    _selectors[0] = LYFCollateralFacet.addCollateral.selector;
    _selectors[1] = LYFCollateralFacet.removeCollateral.selector;
    _selectors[2] = LYFCollateralFacet.transferCollateral.selector;

    ILYFDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_collatFacet),
      ILYFDiamondCut.FacetCutAction.Add,
      _selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_collatFacet, _selectors);
  }

  function deployLYFLiquidationFacet(LYFDiamondCutFacet diamondCutFacet)
    internal
    returns (LYFLiquidationFacet _liquidationFacet, bytes4[] memory _selectors)
  {
    _liquidationFacet = new LYFLiquidationFacet();

    _selectors = new bytes4[](3);
    _selectors[0] = LYFLiquidationFacet.repurchase.selector;
    _selectors[1] = LYFLiquidationFacet.lpLiquidationCall.selector;
    _selectors[2] = LYFLiquidationFacet.liquidationCall.selector;

    ILYFDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_liquidationFacet),
      ILYFDiamondCut.FacetCutAction.Add,
      _selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_liquidationFacet, _selectors);
  }

  function deployLYFOwnershipFacet(LYFDiamondCutFacet diamondCutFacet)
    internal
    returns (LYFOwnershipFacet _ownershipFacet, bytes4[] memory _selectors)
  {
    _ownershipFacet = new LYFOwnershipFacet();

    _selectors = new bytes4[](4);
    _selectors[0] = _ownershipFacet.transferOwnership.selector;
    _selectors[1] = _ownershipFacet.acceptOwnership.selector;
    _selectors[2] = _ownershipFacet.owner.selector;
    _selectors[3] = _ownershipFacet.pendingOwner.selector;

    ILYFDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_ownershipFacet),
      ILYFDiamondCut.FacetCutAction.Add,
      _selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_ownershipFacet, _selectors);
  }

  function deployLYFViewFacet(LYFDiamondCutFacet diamondCutFacet)
    internal
    returns (LYFViewFacet _viewFacet, bytes4[] memory _selectors)
  {
    _viewFacet = new LYFViewFacet();

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

    ILYFDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_viewFacet),
      ILYFDiamondCut.FacetCutAction.Add,
      _selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_viewFacet, _selectors);
  }

  function buildFacetCut(
    address facet,
    ILYFDiamondCut.FacetCutAction cutAction,
    bytes4[] memory selectors
  ) internal pure returns (ILYFDiamondCut.FacetCut[] memory) {
    ILYFDiamondCut.FacetCut[] memory facetCuts = new ILYFDiamondCut.FacetCut[](1);
    facetCuts[0] = ILYFDiamondCut.FacetCut({ action: cutAction, facetAddress: facet, functionSelectors: selectors });

    return facetCuts;
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
