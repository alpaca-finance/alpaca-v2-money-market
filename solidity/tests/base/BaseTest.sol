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
import { CollateralFacet, ICollateralFacet } from "../../contracts/money-market/facets/CollateralFacet.sol";
import { BorrowFacet, IBorrowFacet } from "../../contracts/money-market/facets/BorrowFacet.sol";
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
  MockERC20 internal usdc;
  MockERC20 internal isolateToken;

  MockERC20 internal ibWeth;
  MockERC20 internal ibUsdc;
  MockERC20 internal ibIsolateToken;

  constructor() {
    weth = deployMockErc20("Wrapped Ethereum", "WETH", 18);
    usdc = deployMockErc20("USD COIN", "USDC", 18);
    isolateToken = deployMockErc20("ISOLATETOKEN", "ISOLATETOKEN", 18);

    ibWeth = deployMockErc20("Inerest Bearing Wrapped Ethereum", "IBWETH", 18);
    ibUsdc = deployMockErc20("Inerest USD COIN", "IBUSDC", 18);
    ibIsolateToken = deployMockErc20("IBISOLATETOKEN", "IBISOLATETOKEN", 18);
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
    deployCollateralFacet(DiamondCutFacet(address(moneyMarketDiamond)));
    deployBorrowFacet(DiamondCutFacet(address(moneyMarketDiamond)));
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

    bytes4[] memory selectors = new bytes4[](1);
    selectors[0] = depositFacet.deposit.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(depositFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (depositFacet, selectors);
  }

  function deployCollateralFacet(DiamondCutFacet diamondCutFacet)
    internal
    returns (CollateralFacet, bytes4[] memory)
  {
    CollateralFacet collateralFacet = new CollateralFacet();

    bytes4[] memory selectors = new bytes4[](2);
    selectors[0] = CollateralFacet.addCollateral.selector;
    selectors[1] = CollateralFacet.getCollaterals.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(collateralFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (collateralFacet, selectors);
  }

  function deployBorrowFacet(DiamondCutFacet diamondCutFacet)
    internal
    returns (BorrowFacet, bytes4[] memory)
  {
    BorrowFacet brrowFacet = new BorrowFacet();

    bytes4[] memory selectors = new bytes4[](2);
    selectors[0] = BorrowFacet.borrow.selector;
    selectors[1] = BorrowFacet.getDebtShares.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(brrowFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (brrowFacet, selectors);
  }

  function deployAdminFacet(DiamondCutFacet diamondCutFacet)
    internal
    returns (AdminFacet, bytes4[] memory)
  {
    AdminFacet adminFacet = new AdminFacet();

    bytes4[] memory selectors = new bytes4[](5);
    selectors[0] = adminFacet.setTokenToIbTokens.selector;
    selectors[1] = adminFacet.tokenToIbTokens.selector;
    selectors[2] = adminFacet.ibTokenToTokens.selector;
    selectors[3] = adminFacet.setTokenConfigs.selector;
    selectors[4] = adminFacet.tokenConfigs.selector;

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
