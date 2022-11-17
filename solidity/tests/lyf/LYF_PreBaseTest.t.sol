// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BaseTest, console } from "../base/BaseTest.sol";

// core
import { MoneyMarketDiamond } from "../../contracts/money-market/MoneyMarketDiamond.sol";

// facets
import { DiamondCutFacet, IDiamondCut } from "../../contracts/money-market/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "../../contracts/money-market/facets/DiamondLoupeFacet.sol";
import { AdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";

// interfaces
import { IAdminFacet } from "../../contracts/money-market/interfaces/IAdminFacet.sol";

abstract contract LYF_PreBaseTest is BaseTest {
  address internal moneyMarketDiamond;

  function preSetUp() public virtual {
    moneyMarketDiamond = deployMMPoolDiamond();

    IAdminFacet.IbPair[] memory _ibPair = new IAdminFacet.IbPair[](4);
    _ibPair[0] = IAdminFacet.IbPair({ token: address(weth), ibToken: address(ibWeth) });
    _ibPair[1] = IAdminFacet.IbPair({ token: address(usdc), ibToken: address(ibUsdc) });
    _ibPair[2] = IAdminFacet.IbPair({ token: address(btc), ibToken: address(ibBtc) });
    _ibPair[3] = IAdminFacet.IbPair({ token: address(nativeToken), ibToken: address(ibWNative) });
    IAdminFacet(moneyMarketDiamond).setTokenToIbTokens(_ibPair);
  }

  function deployMMPoolDiamond() internal returns (address) {
    // Deploy DimondCutFacet
    DiamondCutFacet diamondCutFacet = new DiamondCutFacet();

    // Deploy Money Market
    MoneyMarketDiamond _moneyMarketDiamond = new MoneyMarketDiamond(address(this), address(diamondCutFacet));

    deployMMAdminFacet(DiamondCutFacet(address(_moneyMarketDiamond)));

    return (address(_moneyMarketDiamond));
  }

  function deployMMAdminFacet(DiamondCutFacet diamondCutFacet) internal returns (AdminFacet, bytes4[] memory) {
    AdminFacet _adminFacet = new AdminFacet();

    bytes4[] memory selectors = new bytes4[](3);
    selectors[0] = AdminFacet.setTokenToIbTokens.selector;
    selectors[1] = AdminFacet.tokenToIbTokens.selector;
    selectors[2] = AdminFacet.ibTokenToTokens.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildMMFacetCut(
      address(_adminFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_adminFacet, selectors);
  }

  function buildMMFacetCut(
    address facet,
    IDiamondCut.FacetCutAction cutAction,
    bytes4[] memory selectors
  ) internal pure returns (IDiamondCut.FacetCut[] memory) {
    IDiamondCut.FacetCut[] memory facetCuts = new IDiamondCut.FacetCut[](1);
    facetCuts[0] = IDiamondCut.FacetCut({ action: cutAction, facetAddress: facet, functionSelectors: selectors });

    return facetCuts;
  }
}
