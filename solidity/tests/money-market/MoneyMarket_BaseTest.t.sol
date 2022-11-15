// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BaseTest, console } from "../base/BaseTest.sol";

// core
import { MoneyMarketDiamond } from "../../contracts/money-market/MoneyMarketDiamond.sol";

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

// interfaces
import { ICollateralFacet } from "../../contracts/money-market/facets/CollateralFacet.sol";
import { ILendFacet } from "../../contracts/money-market/facets/LendFacet.sol";
import { IAdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";
import { IBorrowFacet } from "../../contracts/money-market/facets/BorrowFacet.sol";
import { INonCollatBorrowFacet } from "../../contracts/money-market/facets/NonCollatBorrowFacet.sol";
import { IRepurchaseFacet } from "../../contracts/money-market/facets/RepurchaseFacet.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// mocks
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockChainLinkPriceOracle } from "../mocks/MockChainLinkPriceOracle.sol";

// libs
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

abstract contract MoneyMarket_BaseTest is BaseTest {
  address internal moneyMarketDiamond;

  IAdminFacet internal adminFacet;
  ILendFacet internal lendFacet;
  ICollateralFacet internal collateralFacet;
  IBorrowFacet internal borrowFacet;
  INonCollatBorrowFacet internal nonCollatBorrowFacet;
  IRepurchaseFacet internal repurchaseFacet;

  MockChainLinkPriceOracle chainLinkOracle;

  function setUp() public virtual {
    (moneyMarketDiamond) = deployPoolDiamond();

    lendFacet = ILendFacet(moneyMarketDiamond);
    collateralFacet = ICollateralFacet(moneyMarketDiamond);
    adminFacet = IAdminFacet(moneyMarketDiamond);
    borrowFacet = IBorrowFacet(moneyMarketDiamond);
    nonCollatBorrowFacet = INonCollatBorrowFacet(moneyMarketDiamond);
    repurchaseFacet = IRepurchaseFacet(moneyMarketDiamond);

    vm.deal(ALICE, 1000 ether);

    weth.mint(ALICE, 1000 ether);
    btc.mint(ALICE, 1000 ether);
    usdc.mint(ALICE, 1000 ether);
    opm.mint(ALICE, 1000 ether);
    isolateToken.mint(ALICE, 1000 ether);

    weth.mint(BOB, 1000 ether);
    btc.mint(BOB, 1000 ether);
    usdc.mint(BOB, 1000 ether);
    isolateToken.mint(BOB, 1000 ether);

    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    btc.approve(moneyMarketDiamond, type(uint256).max);
    usdc.approve(moneyMarketDiamond, type(uint256).max);
    opm.approve(moneyMarketDiamond, type(uint256).max);
    isolateToken.approve(moneyMarketDiamond, type(uint256).max);
    vm.stopPrank();

    vm.startPrank(BOB);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    btc.approve(moneyMarketDiamond, type(uint256).max);
    usdc.approve(moneyMarketDiamond, type(uint256).max);
    isolateToken.approve(moneyMarketDiamond, type(uint256).max);
    vm.stopPrank();

    IAdminFacet.IbPair[] memory _ibPair = new IAdminFacet.IbPair[](4);
    _ibPair[0] = IAdminFacet.IbPair({ token: address(weth), ibToken: address(ibWeth) });
    _ibPair[1] = IAdminFacet.IbPair({ token: address(usdc), ibToken: address(ibUsdc) });
    _ibPair[2] = IAdminFacet.IbPair({ token: address(btc), ibToken: address(ibBtc) });
    _ibPair[3] = IAdminFacet.IbPair({ token: address(wNative), ibToken: address(ibWNative) });
    adminFacet.setTokenToIbTokens(_ibPair);

    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](5);

    _inputs[0] = IAdminFacet.TokenConfigInput({
      token: address(weth),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30e18,
      maxCollateral: 100e18,
      maxToleranceExpiredSecond: block.timestamp
    });

    _inputs[1] = IAdminFacet.TokenConfigInput({
      token: address(usdc),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 1e24,
      maxCollateral: 10e24,
      maxToleranceExpiredSecond: block.timestamp
    });

    _inputs[2] = IAdminFacet.TokenConfigInput({
      token: address(ibWeth),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30e18,
      maxCollateral: 100e18,
      maxToleranceExpiredSecond: block.timestamp
    });

    _inputs[3] = IAdminFacet.TokenConfigInput({
      token: address(btc),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30e18,
      maxCollateral: 100e18,
      maxToleranceExpiredSecond: block.timestamp
    });

    _inputs[4] = IAdminFacet.TokenConfigInput({
      token: address(wNative),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30e18,
      maxCollateral: 100e18,
      maxToleranceExpiredSecond: block.timestamp
    });

    adminFacet.setTokenConfigs(_inputs);
    (_inputs);

    // open isolate token market
    address _ibIsolateToken = lendFacet.openMarket(address(isolateToken));
    ibIsolateToken = MockERC20(_ibIsolateToken);

    //set oracleChecker
    chainLinkOracle = deployMockChainLinkPriceOracle();
    adminFacet.setOracle(address(chainLinkOracle));
    vm.startPrank(DEPLOYER);
    chainLinkOracle.add(address(weth), address(usd), 1 ether, block.timestamp);
    chainLinkOracle.add(address(usdc), address(usd), 1 ether, block.timestamp);
    chainLinkOracle.add(address(isolateToken), address(usd), 1 ether, block.timestamp);
    vm.stopPrank();

    // set repurchases ok
    address[] memory _repurchasers = new address[](1);
    _repurchasers[0] = BOB;
    adminFacet.setRepurchasersOk(_repurchasers, true);

    // adminFacet set native token
    adminFacet.setNativeToken(address(wNative));
  }

  function deployPoolDiamond() internal returns (address) {
    // Deploy DimondCutFacet
    DiamondCutFacet diamondCutFacet = new DiamondCutFacet();

    // Deploy Money Market
    MoneyMarketDiamond _moneyMarketDiamond = new MoneyMarketDiamond(address(this), address(diamondCutFacet));

    deployDiamondLoupeFacet(DiamondCutFacet(address(_moneyMarketDiamond)));
    deployLendFacet(DiamondCutFacet(address(_moneyMarketDiamond)));
    deployCollateralFacet(DiamondCutFacet(address(_moneyMarketDiamond)));
    deployBorrowFacet(DiamondCutFacet(address(_moneyMarketDiamond)));
    deployNonCollatBorrowFacet(DiamondCutFacet(address(_moneyMarketDiamond)));
    deployAdminFacet(DiamondCutFacet(address(_moneyMarketDiamond)));
    deployRepurchaseFacet(DiamondCutFacet(address(_moneyMarketDiamond)));

    initializeDiamond(DiamondCutFacet(address(_moneyMarketDiamond)));

    return (address(_moneyMarketDiamond));
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

  function deployLendFacet(DiamondCutFacet diamondCutFacet) internal returns (LendFacet, bytes4[] memory) {
    LendFacet _lendFacet = new LendFacet();

    bytes4[] memory selectors = new bytes4[](4);
    selectors[0] = LendFacet.deposit.selector;
    selectors[1] = LendFacet.withdraw.selector;
    selectors[2] = LendFacet.getTotalToken.selector;
    selectors[3] = LendFacet.openMarket.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_lendFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_lendFacet, selectors);
  }

  function deployCollateralFacet(DiamondCutFacet diamondCutFacet) internal returns (CollateralFacet, bytes4[] memory) {
    CollateralFacet _collateralFacet = new CollateralFacet();

    bytes4[] memory selectors = new bytes4[](6);
    selectors[0] = CollateralFacet.addCollateral.selector;
    selectors[1] = CollateralFacet.getCollaterals.selector;
    selectors[2] = CollateralFacet.removeCollateral.selector;
    selectors[3] = CollateralFacet.collats.selector;
    selectors[4] = CollateralFacet.transferCollateral.selector;
    selectors[5] = CollateralFacet.subAccountCollatAmount.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_collateralFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_collateralFacet, selectors);
  }

  function deployBorrowFacet(DiamondCutFacet diamondCutFacet) internal returns (BorrowFacet, bytes4[] memory) {
    BorrowFacet _brrowFacet = new BorrowFacet();

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
      address(_brrowFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_brrowFacet, selectors);
  }

  function deployNonCollatBorrowFacet(DiamondCutFacet diamondCutFacet)
    internal
    returns (NonCollatBorrowFacet, bytes4[] memory)
  {
    NonCollatBorrowFacet _nonCollatBorrow = new NonCollatBorrowFacet();

    bytes4[] memory selectors = new bytes4[](7);
    selectors[0] = NonCollatBorrowFacet.nonCollatBorrow.selector;
    selectors[1] = NonCollatBorrowFacet.nonCollatGetDebtValues.selector;
    selectors[2] = NonCollatBorrowFacet.nonCollatGetTotalUsedBorrowedPower.selector;
    selectors[3] = NonCollatBorrowFacet.nonCollatGetDebt.selector;
    selectors[4] = NonCollatBorrowFacet.nonCollatRepay.selector;
    selectors[5] = NonCollatBorrowFacet.nonCollatGetTokenDebt.selector;
    selectors[6] = NonCollatBorrowFacet.nonCollatBorrowLimitUSDValues.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_nonCollatBorrow),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_nonCollatBorrow, selectors);
  }

  function deployAdminFacet(DiamondCutFacet diamondCutFacet) internal returns (AdminFacet, bytes4[] memory) {
    AdminFacet _adminFacet = new AdminFacet();

    bytes4[] memory selectors = new bytes4[](11);
    selectors[0] = AdminFacet.setTokenToIbTokens.selector;
    selectors[1] = AdminFacet.tokenToIbTokens.selector;
    selectors[2] = AdminFacet.ibTokenToTokens.selector;
    selectors[3] = AdminFacet.setTokenConfigs.selector;
    selectors[4] = AdminFacet.tokenConfigs.selector;
    selectors[5] = AdminFacet.setNonCollatBorrower.selector;
    selectors[6] = AdminFacet.setInterestModel.selector;
    selectors[7] = AdminFacet.setOracle.selector;
    selectors[8] = AdminFacet.setRepurchasersOk.selector;
    selectors[9] = AdminFacet.setNonCollatBorrowLimitUSDValues.selector;
    selectors[10] = AdminFacet.setNonCollatInterestModel.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_adminFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_adminFacet, selectors);
  }

  function deployRepurchaseFacet(DiamondCutFacet diamondCutFacet) internal returns (RepurchaseFacet, bytes4[] memory) {
    RepurchaseFacet _repurchaseFacet = new RepurchaseFacet();

    bytes4[] memory selectors = new bytes4[](1);
    selectors[0] = _repurchaseFacet.repurchase.selector;

    IDiamondCut.FacetCut[] memory facetCuts = buildFacetCut(
      address(_repurchaseFacet),
      IDiamondCut.FacetCutAction.Add,
      selectors
    );

    diamondCutFacet.diamondCut(facetCuts, address(0), "");
    return (_repurchaseFacet, selectors);
  }
}
