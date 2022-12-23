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
import { LiquidationFacet, ILiquidationFacet } from "../../../solidity/contracts/money-market/facets/LiquidationFacet.sol";

import { LibDiamond } from "../../../solidity/contracts/money-market/libraries/LibDiamond.sol";

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
    _registerFacet();
    vm.stopBroadcast();
  }

  function _registerFacet() internal returns (address) {
    //  put it here
    address loupeF = address(0x330e3471369D59EdC78A5b4514325aD2411D2389);
    address lendF = address(0x761ba77AA4a34E3ceFbE8a3ae833CD87fa489640);
    address collatF = address(0xea81FC00B3E8CB23815E109153B7D0Db228539c8);
    address borrowF = address(0x6A3C5ec52d9969CC2EE2c136B31635A6c66AE27f);
    address nonBorrowF = address(0xFD84f29F655cED18f62b03C28c83A0b4B008Db21);
    address adminF = address(0x9BfAb04dD186C058DE6B04083A17181b1f4604Cd);
    address repurchaseF = address(0x2A640C16b3A8a86ef7a801441904b8E64f2A66C3);
    address initF = address(0xd4893F6D28dF11aA718fF7842809880043B25404);
    address diamond = address(0xff97548aBfA4B82b8230273f6B55Ec1F038970f1);

    registerDiamondLoupeFacet(DiamondCutFacet(diamond), loupeF);
    registerLendFacet(DiamondCutFacet(diamond), lendF);
    registerCollateralFacet(DiamondCutFacet(diamond), collatF);
    registerBorrowFacet(DiamondCutFacet(diamond), borrowF);
    registerNonCollatBorrowFacet(DiamondCutFacet(diamond), nonBorrowF);
    registerAdminFacet(DiamondCutFacet(diamond), adminF);
    registerLiquidationFacet(DiamondCutFacet(diamond), repurchaseF);
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

  function registerDiamondLoupeFacet(DiamondCutFacet diamondCutFacet, address facet) internal {
    bytes4[] memory selectors = new bytes4[](4);
    selectors[0] = DiamondLoupeFacet.facets.selector;
    selectors[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
    selectors[2] = DiamondLoupeFacet.facetAddresses.selector;
    selectors[3] = DiamondLoupeFacet.facetAddress.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(facet, IDiamondCut.FacetCutAction.Add, selectors);

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
  }

  function registerLendFacet(DiamondCutFacet diamondCutFacet, address facet) internal {
    bytes4[] memory selectors = new bytes4[](4);
    selectors[0] = LendFacet.deposit.selector;
    selectors[1] = LendFacet.withdraw.selector;
    selectors[2] = LendFacet.getTotalToken.selector;
    selectors[3] = LendFacet.openMarket.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(facet, IDiamondCut.FacetCutAction.Add, selectors);

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
  }

  function registerCollateralFacet(DiamondCutFacet diamondCutFacet, address facet) internal {
    bytes4[] memory selectors = new bytes4[](6);
    selectors[0] = CollateralFacet.addCollateral.selector;
    selectors[1] = CollateralFacet.getCollaterals.selector;
    selectors[2] = CollateralFacet.removeCollateral.selector;
    selectors[3] = CollateralFacet.collats.selector;
    selectors[4] = CollateralFacet.transferCollateral.selector;
    selectors[5] = CollateralFacet.subAccountCollatAmount.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(facet, IDiamondCut.FacetCutAction.Add, selectors);

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
  }

  function registerBorrowFacet(DiamondCutFacet diamondCutFacet, address facet) internal {
    bytes4[] memory selectors = new bytes4[](12);
    selectors[0] = BorrowFacet.borrow.selector;
    selectors[2] = BorrowFacet.getTotalBorrowingPower.selector;
    selectors[3] = BorrowFacet.getTotalUsedBorrowedPower.selector;
    selectors[4] = BorrowFacet.getDebt.selector;
    selectors[5] = BorrowFacet.repay.selector;
    selectors[6] = BorrowFacet.getGlobalDebt.selector;
    selectors[7] = BorrowFacet.debtLastAccureTime.selector;
    selectors[8] = BorrowFacet.getGlobalPendingInterest.selector;
    selectors[9] = BorrowFacet.accureInterest.selector;
    selectors[10] = BorrowFacet.getOverCollatDebtValue.selector;
    selectors[11] = BorrowFacet.debtShares.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(facet, IDiamondCut.FacetCutAction.Add, selectors);

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
  }

  function registerNonCollatBorrowFacet(DiamondCutFacet diamondCutFacet, address facet) internal {
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
  }

  function registerAdminFacet(DiamondCutFacet diamondCutFacet, address facet) internal {
    bytes4[] memory selectors = new bytes4[](9);
    selectors[0] = AdminFacet.setIbPairs.selector;
    selectors[1] = AdminFacet.tokenToIbTokens.selector;
    selectors[2] = AdminFacet.ibTokenToTokens.selector;
    selectors[3] = AdminFacet.setTokenConfigs.selector;
    selectors[4] = AdminFacet.setNonCollatBorrower.selector;
    selectors[5] = AdminFacet.setInterestModel.selector;
    selectors[6] = AdminFacet.setOracle.selector;
    selectors[7] = AdminFacet.setRepurchasersOk.selector;
    selectors[8] = AdminFacet.setNonCollatBorrowLimitUSDValues.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(facet, IDiamondCut.FacetCutAction.Add, selectors);

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
  }

  function registerLiquidationFacet(DiamondCutFacet diamondCutFacet, address facet) internal {
    bytes4[] memory selectors = new bytes4[](1);
    selectors[0] = LiquidationFacet.repurchase.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(facet, IDiamondCut.FacetCutAction.Add, selectors);

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
  }
}
