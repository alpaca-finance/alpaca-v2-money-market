// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BaseTest, console } from "../base/BaseTest.sol";

// core
import { LYFDiamond } from "../../contracts/lyf/LYFDiamond.sol";

// facets
import { DiamondCutFacet, IDiamondCut } from "../../contracts/lyf/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "../../contracts/lyf/facets/DiamondLoupeFacet.sol";
import { AdminFacet } from "../../contracts/lyf/facets/AdminFacet.sol";
import { LYFCollateralFacet } from "../../contracts/lyf/facets/LYFCollateralFacet.sol";
import { LYFFarmFacet } from "../../contracts/lyf/facets/LYFFarmFacet.sol";

// initializers
import { DiamondInit } from "../../contracts/lyf/initializers/DiamondInit.sol";

// interfaces
import { IAdminFacet } from "../../contracts/lyf/interfaces/IAdminFacet.sol";
import { ILYFCollateralFacet } from "../../contracts/lyf/interfaces/ILYFCollateralFacet.sol";
import { ILYFFarmFacet } from "../../contracts/lyf/interfaces/ILYFFarmFacet.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPancakeRouter02 } from "../../contracts/lyf/interfaces/IPancakeRouter02.sol";

// mocks
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockLPToken } from "../mocks/MockLPToken.sol";
import { MockChainLinkPriceOracle } from "../mocks/MockChainLinkPriceOracle.sol";
import { MockRouter } from "../mocks/MockRouter.sol";

// libs
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";

// peripherals
import { PancakeswapV2StrategyAddTwoSidesOptimal } from "../../contracts/lyf/strats/PancakeswapV2StrategyAddTwoSidesOptimal.sol";

abstract contract LYF_BaseTest is BaseTest {
  address internal lyfDiamond;

  IAdminFacet internal adminFacet;
  ILYFCollateralFacet internal collateralFacet;
  ILYFFarmFacet internal farmFacet;

  MockLPToken internal wethUsdcLPToken;

  MockChainLinkPriceOracle chainLinkOracle;

  MockRouter internal mockRouter;
  PancakeswapV2StrategyAddTwoSidesOptimal internal addStrat;

  function setUp() public virtual {
    (lyfDiamond) = deployPoolDiamond();

    adminFacet = IAdminFacet(lyfDiamond);
    collateralFacet = ILYFCollateralFacet(lyfDiamond);
    farmFacet = ILYFFarmFacet(lyfDiamond);

    weth.mint(ALICE, 1000 ether);
    usdc.mint(ALICE, 1000 ether);
    weth.mint(BOB, 1000 ether);
    usdc.mint(BOB, 1000 ether);
    vm.startPrank(ALICE);
    weth.approve(lyfDiamond, type(uint256).max);
    usdc.approve(lyfDiamond, type(uint256).max);
    vm.stopPrank();

    vm.startPrank(BOB);
    weth.approve(lyfDiamond, type(uint256).max);
    usdc.approve(lyfDiamond, type(uint256).max);
    vm.stopPrank();
    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](2);

    _inputs[0] = IAdminFacet.TokenConfigInput({
      token: address(weth),
      tier: LibLYF01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30e18,
      maxCollateral: 100e18,
      maxToleranceExpiredSecond: block.timestamp
    });

    _inputs[1] = IAdminFacet.TokenConfigInput({
      token: address(usdc),
      tier: LibLYF01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 1e24,
      maxCollateral: 10e24,
      maxToleranceExpiredSecond: block.timestamp
    });

    adminFacet.setTokenConfigs(_inputs);

    wethUsdcLPToken = new MockLPToken("MOCK LP", "MOCK LP", 18, address(weth), address(usdc));

    mockRouter = new MockRouter(address(wethUsdcLPToken));

    addStrat = new PancakeswapV2StrategyAddTwoSidesOptimal(IPancakeRouter02(address(mockRouter)));

    wethUsdcLPToken.mint(address(mockRouter), 1000000 ether);
  }

  function deployPoolDiamond() internal returns (address) {
    // Deploy DimondCutFacet
    DiamondCutFacet diamondCutFacet = new DiamondCutFacet();

    // Deploy LYF
    LYFDiamond _lyfDiamond = new LYFDiamond(address(this), address(diamondCutFacet));

    deployAdminFacet(DiamondCutFacet(address(_lyfDiamond)));
    deployLYFCollateralFacet(DiamondCutFacet(address(_lyfDiamond)));
    deployLYFFarmFacet(DiamondCutFacet(address(_lyfDiamond)));

    initializeDiamond(DiamondCutFacet(address(_lyfDiamond)));

    return (address(_lyfDiamond));
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
    DiamondLoupeFacet _diamondLoupeFacet = new DiamondLoupeFacet();

    bytes4[] memory selectors = new bytes4[](4);
    selectors[0] = DiamondLoupeFacet.facets.selector;
    selectors[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
    selectors[2] = DiamondLoupeFacet.facetAddresses.selector;
    selectors[3] = DiamondLoupeFacet.facetAddress.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_diamondLoupeFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_diamondLoupeFacet, selectors);
  }

  function deployLYFFarmFacet(DiamondCutFacet diamondCutFacet) internal returns (LYFFarmFacet, bytes4[] memory) {
    LYFFarmFacet _farmFacet = new LYFFarmFacet();

    bytes4[] memory selectors = new bytes4[](12);
    selectors[0] = _farmFacet.addFarmPosition.selector;
    selectors[1] = _farmFacet.getDebtShares.selector;
    selectors[2] = _farmFacet.getTotalBorrowingPower.selector;
    selectors[3] = _farmFacet.getTotalUsedBorrowedPower.selector;
    selectors[4] = _farmFacet.getDebt.selector;
    selectors[5] = _farmFacet.repay.selector;
    selectors[6] = _farmFacet.getGlobalDebt.selector;
    selectors[7] = _farmFacet.debtLastAccureTime.selector;
    selectors[8] = _farmFacet.pendingInterest.selector;
    selectors[9] = _farmFacet.accureInterest.selector;
    selectors[10] = _farmFacet.debtValues.selector;
    selectors[11] = _farmFacet.debtShares.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_farmFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_farmFacet, selectors);
  }

  function deployAdminFacet(DiamondCutFacet diamondCutFacet) internal returns (AdminFacet, bytes4[] memory) {
    AdminFacet _adminFacet = new AdminFacet();

    bytes4[] memory selectors = new bytes4[](3);
    selectors[0] = AdminFacet.setOracle.selector;
    selectors[1] = AdminFacet.oracle.selector;
    selectors[2] = AdminFacet.setTokenConfigs.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_adminFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_adminFacet, selectors);
  }

  function deployLYFCollateralFacet(DiamondCutFacet diamondCutFacet)
    internal
    returns (LYFCollateralFacet _collatFacet, bytes4[] memory _selectors)
  {
    _collatFacet = new LYFCollateralFacet();

    _selectors = new bytes4[](5);
    _selectors[0] = LYFCollateralFacet.addCollateral.selector;
    _selectors[1] = LYFCollateralFacet.removeCollateral.selector;
    _selectors[2] = LYFCollateralFacet.collats.selector;
    _selectors[3] = LYFCollateralFacet.subAccountCollatAmount.selector;
    _selectors[4] = LYFCollateralFacet.getCollaterals.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_collatFacet),
      IDiamondCut.FacetCutAction.Add,
      _selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_collatFacet, _selectors);
  }
}
