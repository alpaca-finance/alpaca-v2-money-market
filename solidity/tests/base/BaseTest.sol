// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { DSTest } from "./DSTest.sol";

import { VM } from "../utils/VM.sol";
import { console } from "../utils/console.sol";

// core
import { MoneyMarketDiamond } from "../../contracts/money-market/MoneyMarketDiamond.sol";

// facets
import { DiamondCutFacet, IDiamondCut } from "../../contracts/money-market/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "../../contracts/money-market/facets/DiamondLoupeFacet.sol";
import { DepositFacet, IDepositFacet } from "../../contracts/money-market/facets/DepositFacet.sol";
import { AdminFacet, IAdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";

// initializers
import { DiamondInit } from "../../contracts/money-market/initializers/DiamondInit.sol";

// Mocks
import { MockERC20 } from "../mocks/MockERC20.sol";

contract BaseTest is DSTest {
  address internal constant ALICE = address(0x88);
  address internal constant BOB = address(0x168);
  address internal constant CAT = address(0x99);
  address internal constant EVE = address(0x55);

  VM internal constant vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

  MockERC20 internal weth;

  MockERC20 internal ibWeth;

  constructor() {
    weth = deployMockErc20("Wrapped Ethereum", "WETH", 18);

    ibWeth = deployMockErc20("Inerest Bearing Wrapped Ethereum", "IBWETH", 18);
  }

  function deployPoolDiamond() internal returns (address) {
    // Deploy DimondCutFacet
    DiamondCutFacet diamondCutFacet = new DiamondCutFacet();

    // Deploy Money Market
    MoneyMarketDiamond moneyMarketDiamond = new MoneyMarketDiamond(
      address(this),
      address(diamondCutFacet)
    );

    deployDiamondLoupeFacet(DiamondCutFacet(address(moneyMarketDiamond)));
    deployDepositFacet(DiamondCutFacet(address(moneyMarketDiamond)));
    deployAdminFacet(DiamondCutFacet(address(moneyMarketDiamond)));

    initializeDiamond(DiamondCutFacet(address(moneyMarketDiamond)));

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
    facetCuts[0] = IDiamondCut.FacetCut({
      action: cutAction,
      facetAddress: facet,
      functionSelectors: selectors
    });

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

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (diamondLoupeFacet, selectors);
  }

  function deployDepositFacet(DiamondCutFacet diamondCutFacet)
    internal
    returns (DepositFacet, bytes4[] memory)
  {
    DepositFacet depositFacet = new DepositFacet();

    bytes4[] memory selectors = new bytes4[](2);
    selectors[0] = depositFacet.deposit.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(depositFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (depositFacet, selectors);
  }

  function deployAdminFacet(DiamondCutFacet diamondCutFacet)
    internal
    returns (AdminFacet, bytes4[] memory)
  {
    AdminFacet adminFacet = new AdminFacet();

    bytes4[] memory selectors = new bytes4[](3);
    selectors[0] = adminFacet.setTokenToIbTokens.selector;
    selectors[1] = adminFacet.tokenToIbTokens.selector;
    selectors[2] = adminFacet.ibTokenToTokens.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(adminFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (adminFacet, selectors);
  }

  function deployMockErc20(
    string memory name,
    string memory symbol,
    uint8 decimals
  ) internal returns (MockERC20) {
    return new MockERC20(name, symbol, decimals);
  }
}
