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

contract InitialDiamond is Script {
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

    address alpacaDeployer = address(0xC44f82b07Ab3E691F826951a6E335E1bC1bB0B51);
    address deployer = vm.addr(deployerPrivateKey);
    if (alpacaDeployer == deployer) {
      vm.startBroadcast(deployer);
    } else {
      vm.startBroadcast();
    }
    _deployPoolDiamond(alpacaDeployer);
    vm.stopBroadcast();
  }

  function _deployPoolDiamond(address owner) internal returns (address) {
    // Deploy DimondCutFacet
    DiamondCutFacet diamondCutFacet = new DiamondCutFacet();

    // Deploy Money Market
    MoneyMarketDiamond moneyMarketDiamond = new MoneyMarketDiamond(owner, address(diamondCutFacet));
    console.log("diamondCutFacet", address(diamondCutFacet));
    console.log("moneyMarketDiamond", address(moneyMarketDiamond));

    // deployDiamondLoupeFacet(DiamondCutFacet(address(moneyMarketDiamond)));

    // deployLendFacet(DiamondCutFacet(address(moneyMarketDiamond)));
    // deployCollateralFacet(DiamondCutFacet(address(moneyMarketDiamond)));
    // deployBorrowFacet(DiamondCutFacet(address(moneyMarketDiamond)));
    // deployNonCollatBorrowFacet(DiamondCutFacet(address(moneyMarketDiamond)));
    // deployAdminFacet(DiamondCutFacet(address(moneyMarketDiamond)));
    // deployRepurchaseFacet(DiamondCutFacet(address(moneyMarketDiamond)));

    // initializeDiamond(DiamondCutFacet(address(moneyMarketDiamond)));

    return (address(moneyMarketDiamond));
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
    DiamondLoupeFacet diamondLoupeFacet = new DiamondLoupeFacet();

    bytes4[] memory selectors = new bytes4[](4);
    selectors[0] = DiamondLoupeFacet.facets.selector;
    selectors[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
    selectors[2] = DiamondLoupeFacet.facetAddresses.selector;
    selectors[3] = DiamondLoupeFacet.facetAddress.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(diamondLoupeFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    //diamondCutFacet.diamondCut(facetCuts, address(0), "");

    return (diamondLoupeFacet, selectors);
  }
}
