// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { DSTest } from "./DSTest.sol";

import { VM } from "../utils/VM.sol";
import { console } from "../utils/console.sol";

// core
import { MoneyMarketDiamond } from "../../contracts/money-market/MoneyMarketDiamond.sol";

// oracle
import { SimplePriceOracle } from "../../contracts/oracle/SimplePriceOracle.sol";
import { ChainLinkPriceOracle } from "../../contracts/oracle/ChainLinkPriceOracle.sol";
import { OracleChecker, IOracleChecker, IPriceOracle } from "../../contracts/oracle/OracleChecker.sol";

// facets
import { DiamondCutFacet, IDiamondCut } from "../../contracts/money-market/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "../../contracts/money-market/facets/DiamondLoupeFacet.sol";
import { LendFacet, ILendFacet } from "../../contracts/money-market/facets/LendFacet.sol";
import { CollateralFacet, ICollateralFacet } from "../../contracts/money-market/facets/CollateralFacet.sol";
import { BorrowFacet, IBorrowFacet } from "../../contracts/money-market/facets/BorrowFacet.sol";
import { NonCollatBorrowFacet, INonCollatBorrowFacet } from "../../contracts/money-market/facets/NonCollatBorrowFacet.sol";
import { AdminFacet, IAdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";
import { RepurchaseFacet, IRepurchaseFacet } from "../../contracts/money-market/facets/RepurchaseFacet.sol";

// initializers
import { DiamondInit } from "../../contracts/money-market/initializers/DiamondInit.sol";

// Mocks
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockChainLinkPriceOracle } from "../mocks/MockChainLinkPriceOracle.sol";

import { console } from "../utils/console.sol";

contract BaseTest is DSTest {
  address internal constant DEPLOYER = address(0x01);
  address internal constant ALICE = address(0x88);
  address internal constant BOB = address(0x168);
  address internal constant CAT = address(0x99);
  address internal constant EVE = address(0x55);

  VM internal constant vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

  MockERC20 internal weth;
  MockERC20 internal usdc;
  MockERC20 internal btc;
  MockERC20 internal opm; // open market token
  MockERC20 internal usd;
  MockERC20 internal isolateToken;

  MockERC20 internal ibWeth;
  MockERC20 internal ibBtc;
  MockERC20 internal ibUsdc;
  MockERC20 internal ibIsolateToken;

  OracleChecker internal oracleChecker;

  constructor() {
    weth = deployMockErc20("Wrapped Ethereum", "WETH", 18);
    btc = deployMockErc20("Bitcoin", "BTC", 18);
    usdc = deployMockErc20("USD COIN", "USDC", 18);
    usd = deployMockErc20("USD FOR CHAINLINK", "USD", 18);
    opm = deployMockErc20("OPM Token", "OPM", 9);
    isolateToken = deployMockErc20("ISOLATETOKEN", "ISOLATETOKEN", 18);

    ibWeth = deployMockErc20("Inerest Bearing Wrapped Ethereum", "IBWETH", 18);
    ibBtc = deployMockErc20("Inerest Bearing Bitcoin", "IBBTC", 18);
    ibUsdc = deployMockErc20("Inerest USD COIN", "IBUSDC", 18);
    ibIsolateToken = deployMockErc20("IBISOLATETOKEN", "IBISOLATETOKEN", 18);
  }

  function deployPoolDiamond() internal returns (address) {
    // Deploy DimondCutFacet
    DiamondCutFacet diamondCutFacet = new DiamondCutFacet();

    // Deploy Money Market
    MoneyMarketDiamond moneyMarketDiamond = new MoneyMarketDiamond(address(this), address(diamondCutFacet));

    deployDiamondLoupeFacet(DiamondCutFacet(address(moneyMarketDiamond)));
    deployLendFacet(DiamondCutFacet(address(moneyMarketDiamond)));
    deployCollateralFacet(DiamondCutFacet(address(moneyMarketDiamond)));
    deployBorrowFacet(DiamondCutFacet(address(moneyMarketDiamond)));
    deployNonCollatBorrowFacet(DiamondCutFacet(address(moneyMarketDiamond)));
    deployAdminFacet(DiamondCutFacet(address(moneyMarketDiamond)));
    deployRepurchaseFacet(DiamondCutFacet(address(moneyMarketDiamond)));

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

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (diamondLoupeFacet, selectors);
  }

  function deployLendFacet(DiamondCutFacet diamondCutFacet) internal returns (LendFacet, bytes4[] memory) {
    LendFacet lendFacet = new LendFacet();

    bytes4[] memory selectors = new bytes4[](4);
    selectors[0] = lendFacet.deposit.selector;
    selectors[1] = lendFacet.withdraw.selector;
    selectors[2] = lendFacet.getTotalToken.selector;
    selectors[3] = lendFacet.openMarket.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(lendFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (lendFacet, selectors);
  }

  function deployCollateralFacet(DiamondCutFacet diamondCutFacet) internal returns (CollateralFacet, bytes4[] memory) {
    CollateralFacet collateralFacet = new CollateralFacet();

    bytes4[] memory selectors = new bytes4[](6);
    selectors[0] = CollateralFacet.addCollateral.selector;
    selectors[1] = CollateralFacet.getCollaterals.selector;
    selectors[2] = CollateralFacet.removeCollateral.selector;
    selectors[3] = CollateralFacet.collats.selector;
    selectors[4] = CollateralFacet.transferCollateral.selector;
    selectors[5] = CollateralFacet.subAccountCollatAmount.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(collateralFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (collateralFacet, selectors);
  }

  function deployBorrowFacet(DiamondCutFacet diamondCutFacet) internal returns (BorrowFacet, bytes4[] memory) {
    BorrowFacet brrowFacet = new BorrowFacet();

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

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(brrowFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (brrowFacet, selectors);
  }

  function deployNonCollatBorrowFacet(DiamondCutFacet diamondCutFacet)
    internal
    returns (NonCollatBorrowFacet, bytes4[] memory)
  {
    NonCollatBorrowFacet nonCollatBorrow = new NonCollatBorrowFacet();

    bytes4[] memory selectors = new bytes4[](6);
    selectors[0] = NonCollatBorrowFacet.nonCollatBorrow.selector;
    selectors[1] = NonCollatBorrowFacet.nonCollatGetDebtValues.selector;
    selectors[2] = NonCollatBorrowFacet.nonCollatGetTotalUsedBorrowedPower.selector;
    selectors[3] = NonCollatBorrowFacet.nonCollatGetDebt.selector;
    selectors[4] = NonCollatBorrowFacet.nonCollatRepay.selector;
    selectors[5] = NonCollatBorrowFacet.nonCollatGetTokenDebt.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(nonCollatBorrow),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (nonCollatBorrow, selectors);
  }

  function deployAdminFacet(DiamondCutFacet diamondCutFacet) internal returns (AdminFacet, bytes4[] memory) {
    AdminFacet adminFacet = new AdminFacet();

    bytes4[] memory selectors = new bytes4[](9);
    selectors[0] = adminFacet.setTokenToIbTokens.selector;
    selectors[1] = adminFacet.tokenToIbTokens.selector;
    selectors[2] = adminFacet.ibTokenToTokens.selector;
    selectors[3] = adminFacet.setTokenConfigs.selector;
    selectors[4] = adminFacet.tokenConfigs.selector;
    selectors[5] = adminFacet.setNonCollatBorrower.selector;
    selectors[6] = adminFacet.setInterestModel.selector;
    selectors[7] = adminFacet.setOracleChecker.selector;
    selectors[8] = adminFacet.setRepurchasersOk.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(adminFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (adminFacet, selectors);
  }

  function deployRepurchaseFacet(DiamondCutFacet diamondCutFacet) internal returns (RepurchaseFacet, bytes4[] memory) {
    RepurchaseFacet repurchaseFacet = new RepurchaseFacet();

    bytes4[] memory selectors = new bytes4[](1);
    selectors[0] = repurchaseFacet.repurchase.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(repurchaseFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (repurchaseFacet, selectors);
  }

  function deployMockErc20(
    string memory name,
    string memory symbol,
    uint8 decimals
  ) internal returns (MockERC20) {
    return new MockERC20(name, symbol, decimals);
  }

  function deployOracleChecker(address _oracle, address _usd) internal returns (OracleChecker) {
    OracleChecker checker = new OracleChecker();
    checker.initialize(IPriceOracle(_oracle), _usd);
    address oldOwner = checker.owner();
    vm.prank(oldOwner);
    checker.transferOwnership(DEPLOYER);
    return checker;
  }

  function deployMockChainLinkPriceOracle() internal returns (MockChainLinkPriceOracle) {
    return new MockChainLinkPriceOracle();
  }
}
