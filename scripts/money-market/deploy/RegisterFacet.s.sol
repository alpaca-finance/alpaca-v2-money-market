// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script, console } from "solidity/tests/utils/Script.sol";
// core
import { MoneyMarketDiamond } from "../../../solidity/contracts/money-market/MoneyMarketDiamond.sol";

// facets
import { DiamondCutFacet, IDiamondCut } from "../../../solidity/contracts/money-market/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "../../../solidity/contracts/money-market/facets/DiamondLoupeFacet.sol";
import { LendFacet, ILendFacet } from "../../../solidity/contracts/money-market/facets/LendFacet.sol";
import { CollateralFacet, ICollateralFacet } from "../../../solidity/contracts/money-market/facets/CollateralFacet.sol";
import { BorrowFacet, IBorrowFacet } from "../../../solidity/contracts/money-market/facets/BorrowFacet.sol";
import { NonCollatBorrowFacet, INonCollatBorrowFacet } from "../../../solidity/contracts/money-market/facets/NonCollatBorrowFacet.sol";
import { AdminFacet, IAdminFacet } from "../../../solidity/contracts/money-market/facets/AdminFacet.sol";
import { RepurchaseFacet, IRepurchaseFacet } from "../../../solidity/contracts/money-market/facets/RepurchaseFacet.sol";

// initializers
import { DiamondInit } from "../../../solidity/contracts/money-market/initializers/DiamondInit.sol";

contract RegisterFacet is Script {
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

    address alpacaDeployer = address(0xC44f82b07Ab3E691F826951a6E335E1bC1bB0B51);
    address deployer = vm.addr(deployerPrivateKey);
    if (alpacaDeployer == deployer) {
      vm.startBroadcast(deployer);
    } else {
      vm.startBroadcast();
    }
    _registerFacet(alpacaDeployer);
    vm.stopBroadcast();
  }

  function _registerFacet(address owner) internal returns (address) {
    // TODO put it here
    address diamond = address(0x6e5bE6902a4Df859B64C4400009EF4039e87Ba98);
    address loupeF = address(0xB2835ceC6b58E51133090392691Bdccb06B4D188);
    address lendF = address(0x9BfAb04dD186C058DE6B04083A17181b1f4604Cd);
    address collatF = address(0xea81FC00B3E8CB23815E109153B7D0Db228539c8);
    address borrowF = address(0x761ba77AA4a34E3ceFbE8a3ae833CD87fa489640);
    address nonBorrowF = address(0x6A3C5ec52d9969CC2EE2c136B31635A6c66AE27f);
    address adminF = address(0x330e3471369D59EdC78A5b4514325aD2411D2389);
    address repurchaseF = address(0xd4893F6D28dF11aA718fF7842809880043B25404);
    address initF = address(0x2A640C16b3A8a86ef7a801441904b8E64f2A66C3);

    deployDiamondLoupeFacet(DiamondCutFacet(diamond), loupeF);
    deployLendFacet(DiamondCutFacet(diamond), lendF);
    deployCollateralFacet(DiamondCutFacet(diamond), collatF);
    deployBorrowFacet(DiamondCutFacet(diamond), borrowF);
    deployNonCollatBorrowFacet(DiamondCutFacet(diamond), nonBorrowF);
    deployAdminFacet(DiamondCutFacet(diamond), adminF);
    deployRepurchaseFacet(DiamondCutFacet(diamond), repurchaseF);
    initializeDiamond(DiamondCutFacet(diamond), initF);

    return (diamond);
  }

  function initializeDiamond(DiamondCutFacet diamondCutFacet, address facet) internal {
    // Deploy DiamondInit
    IDiamondCut.FacetCut[] memory facetCuts = new IDiamondCut.FacetCut[](0);

    // make lib diamond call init
    diamondCutFacet.diamondCut(facetCuts, facet, abi.encodeWithSelector(bytes4(keccak256("init()"))));
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

  function deployDiamondLoupeFacet(DiamondCutFacet diamondCutFacet, address facet)
    internal
    returns (DiamondLoupeFacet, bytes4[] memory)
  {
    bytes4[] memory selectors = new bytes4[](4);
    selectors[0] = DiamondLoupeFacet.facets.selector;
    selectors[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
    selectors[2] = DiamondLoupeFacet.facetAddresses.selector;
    selectors[3] = DiamondLoupeFacet.facetAddress.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(facet, IDiamondCut.FacetCutAction.Add, selectors);

    diamondCutFacet.diamondCut(facetCuts, address(0), "");

    return (diamondLoupeFacet, selectors);
  }

  function deployLendFacet(DiamondCutFacet diamondCutFacet, address facet)
    internal
    returns (LendFacet, bytes4[] memory)
  {
    bytes4[] memory selectors = new bytes4[](4);
    selectors[0] = lendFacet.deposit.selector;
    selectors[1] = lendFacet.withdraw.selector;
    selectors[2] = lendFacet.getTotalToken.selector;
    selectors[3] = lendFacet.openMarket.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(facet, IDiamondCut.FacetCutAction.Add, selectors);

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (lendFacet, selectors);
  }

  function deployCollateralFacet(DiamondCutFacet diamondCutFacet, address facet)
    internal
    returns (CollateralFacet, bytes4[] memory)
  {
    bytes4[] memory selectors = new bytes4[](6);
    selectors[0] = CollateralFacet.addCollateral.selector;
    selectors[1] = CollateralFacet.getCollaterals.selector;
    selectors[2] = CollateralFacet.removeCollateral.selector;
    selectors[3] = CollateralFacet.collats.selector;
    selectors[4] = CollateralFacet.transferCollateral.selector;
    selectors[5] = CollateralFacet.subAccountCollatAmount.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(facet, IDiamondCut.FacetCutAction.Add, selectors);

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (collateralFacet, selectors);
  }

  function deployBorrowFacet(DiamondCutFacet diamondCutFacet, address facet)
    internal
    returns (BorrowFacet, bytes4[] memory)
  {
    bytes4[] memory selectors = new bytes4[](12);
    selectors[0] = BorrowFacet.borrow.selector;
    selectors[1] = BorrowFacet.getDebtShares.selector;
    selectors[2] = BorrowFacet.getTotalBorrowingPower.selector;
    selectors[3] = BorrowFacet.getTotalUsedBorrowedPower.selector;
    selectors[4] = BorrowFacet.getDebt.selector;
    selectors[5] = BorrowFacet.repay.selector;
    selectors[6] = BorrowFacet.getGlobalDebt.selector;
    selectors[7] = BorrowFacet.debtLastAccureTime.selector;
    selectors[8] = BorrowFacet.pendingInterest.selector;
    selectors[9] = BorrowFacet.accureInterest.selector;
    selectors[10] = BorrowFacet.debtValues.selector;
    selectors[11] = BorrowFacet.debtShares.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(facet, IDiamondCut.FacetCutAction.Add, selectors);

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (brrowFacet, selectors);
  }

  function deployNonCollatBorrowFacet(DiamondCutFacet diamondCutFacet, address facet)
    internal
    returns (NonCollatBorrowFacet, bytes4[] memory)
  {
    bytes4[] memory selectors = new bytes4[](7);
    selectors[0] = NonCollatBorrowFacet.nonCollatBorrow.selector;
    selectors[1] = NonCollatBorrowFacet.nonCollatGetDebtValues.selector;
    selectors[2] = NonCollatBorrowFacet.nonCollatGetTotalUsedBorrowedPower.selector;
    selectors[3] = NonCollatBorrowFacet.nonCollatGetDebt.selector;
    selectors[4] = NonCollatBorrowFacet.nonCollatRepay.selector;
    selectors[5] = NonCollatBorrowFacet.nonCollatGetTokenDebt.selector;
    selectors[6] = NonCollatBorrowFacet.nonCollatBorrowLimitUSDValues.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(facet, IDiamondCut.FacetCutAction.Add, selectors);

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (nonCollatBorrow, selectors);
  }

  function deployAdminFacet(DiamondCutFacet diamondCutFacet, address facet)
    internal
    returns (AdminFacet, bytes4[] memory)
  {
    bytes4[] memory selectors = new bytes4[](10);
    selectors[0] = adminFacet.setTokenToIbTokens.selector;
    selectors[1] = adminFacet.tokenToIbTokens.selector;
    selectors[2] = adminFacet.ibTokenToTokens.selector;
    selectors[3] = adminFacet.setTokenConfigs.selector;
    selectors[4] = adminFacet.tokenConfigs.selector;
    selectors[5] = adminFacet.setNonCollatBorrower.selector;
    selectors[6] = adminFacet.setInterestModel.selector;
    selectors[7] = adminFacet.setOracle.selector;
    selectors[8] = adminFacet.setRepurchasersOk.selector;
    selectors[9] = adminFacet.setNonCollatBorrowLimitUSDValues.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(facet, IDiamondCut.FacetCutAction.Add, selectors);

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (adminFacet, selectors);
  }

  function deployRepurchaseFacet(DiamondCutFacet diamondCutFacet, address facet)
    internal
    returns (RepurchaseFacet, bytes4[] memory)
  {
    bytes4[] memory selectors = new bytes4[](1);
    selectors[0] = repurchaseFacet.repurchase.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(facet, IDiamondCut.FacetCutAction.Add, selectors);

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (repurchaseFacet, selectors);
  }
}
