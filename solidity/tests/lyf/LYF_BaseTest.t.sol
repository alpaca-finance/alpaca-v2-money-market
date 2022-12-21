// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BaseTest, console } from "../base/BaseTest.sol";

// core
import { LYFDiamond } from "../../contracts/lyf/LYFDiamond.sol";
import { MoneyMarketDiamond } from "../../contracts/money-market/MoneyMarketDiamond.sol";

// facets
import { DiamondCutFacet, IDiamondCut } from "../../contracts/lyf/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "../../contracts/lyf/facets/DiamondLoupeFacet.sol";
import { LYFAdminFacet } from "../../contracts/lyf/facets/LYFAdminFacet.sol";
import { LYFCollateralFacet } from "../../contracts/lyf/facets/LYFCollateralFacet.sol";
import { LYFFarmFacet } from "../../contracts/lyf/facets/LYFFarmFacet.sol";

// initializers
import { DiamondInit } from "../../contracts/lyf/initializers/DiamondInit.sol";

// interfaces
import { ILYFAdminFacet } from "../../contracts/lyf/interfaces/ILYFAdminFacet.sol";
import { ILYFCollateralFacet } from "../../contracts/lyf/interfaces/ILYFCollateralFacet.sol";
import { ILYFFarmFacet } from "../../contracts/lyf/interfaces/ILYFFarmFacet.sol";
import { ILYFLiquidationFacet } from "../../contracts/lyf/interfaces/ILYFLiquidationFacet.sol";
import { ILYFOwnershipFacet } from "../../contracts/lyf/interfaces/ILYFOwnershipFacet.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRouterLike } from "../../contracts/lyf/interfaces/IRouterLike.sol";
import { IAdminFacet } from "../../contracts/money-market/interfaces/IAdminFacet.sol";
import { ILendFacet } from "../../contracts/money-market/interfaces/ILendFacet.sol";
import { IPriceOracle } from "../../contracts/oracle/interfaces/IPriceOracle.sol";
import { IAlpacaV2Oracle } from "../../contracts/oracle/AlpacaV2Oracle.sol";
// mocks
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockLPToken } from "../mocks/MockLPToken.sol";
import { MockChainLinkPriceOracle } from "../mocks/MockChainLinkPriceOracle.sol";
import { MockRouter } from "../mocks/MockRouter.sol";
import { MockMasterChef } from "../mocks/MockMasterChef.sol";
import { MockInterestModel } from "../mocks/MockInterestModel.sol";
import { MockAlpacaV2Oracle } from "../mocks/MockAlpacaV2Oracle.sol";

// libs
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";

// peripherals
import { PancakeswapV2Strategy } from "../../contracts/lyf/strats/PancakeswapV2Strategy.sol";
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// helper
import { MMDiamondDeployer } from "../helper/MMDiamondDeployer.sol";
import { LYFDiamondDeployer } from "../helper/LYFDiamondDeployer.sol";

// oracle
import { OracleMedianizer } from "../../contracts/oracle/OracleMedianizer.sol";

abstract contract LYF_BaseTest is BaseTest {
  address internal lyfDiamond;
  address internal moneyMarketDiamond;
  address internal treasury = address(888);

  LYFAdminFacet internal adminFacet;
  ILYFCollateralFacet internal collateralFacet;
  ILYFFarmFacet internal farmFacet;
  ILYFLiquidationFacet internal liquidationFacet;
  ILYFOwnershipFacet internal ownershipFacet;

  MockLPToken internal wethUsdcLPToken;
  uint256 internal wethUsdcPoolId;

  MockChainLinkPriceOracle chainLinkOracle;

  MockRouter internal mockRouter;
  PancakeswapV2Strategy internal addStrat;
  MockMasterChef internal masterChef;
  MockAlpacaV2Oracle internal mockOracle;

  uint256 constant reinvestThreshold = 1e18;

  function setUp() public virtual {
    lyfDiamond = LYFDiamondDeployer.deployPoolDiamond();
    moneyMarketDiamond = MMDiamondDeployer.deployPoolDiamond(address(nativeToken), address(nativeRelayer));
    setUpMM();

    adminFacet = LYFAdminFacet(lyfDiamond);
    collateralFacet = ILYFCollateralFacet(lyfDiamond);
    farmFacet = ILYFFarmFacet(lyfDiamond);
    liquidationFacet = ILYFLiquidationFacet(lyfDiamond);
    ownershipFacet = ILYFOwnershipFacet(lyfDiamond);

    vm.startPrank(ALICE);
    weth.approve(lyfDiamond, type(uint256).max);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    usdc.approve(lyfDiamond, type(uint256).max);
    btc.approve(lyfDiamond, type(uint256).max);
    ibWeth.approve(lyfDiamond, type(uint256).max);
    vm.stopPrank();

    vm.startPrank(BOB);
    weth.approve(lyfDiamond, type(uint256).max);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    usdc.approve(lyfDiamond, type(uint256).max);
    usdc.approve(moneyMarketDiamond, type(uint256).max);
    ibWeth.approve(lyfDiamond, type(uint256).max);
    ibUsdc.approve(lyfDiamond, type(uint256).max);
    vm.stopPrank();

    // DEPLOY MASTERCHEF
    masterChef = new MockMasterChef(address(cake));

    // MASTERCHEF POOLID
    wethUsdcPoolId = 1;

    // mock LP, Router and Stratgy
    wethUsdcLPToken = new MockLPToken("MOCK LP", "MOCK LP", 18, address(weth), address(usdc));

    mockRouter = new MockRouter(address(wethUsdcLPToken));

    masterChef.addLendingPool(address(wethUsdcLPToken), wethUsdcPoolId);

    addStrat = new PancakeswapV2Strategy(IRouterLike(address(mockRouter)));
    address[] memory stratWhitelistedCallers = new address[](1);
    stratWhitelistedCallers[0] = lyfDiamond;
    addStrat.setWhitelistedCallers(stratWhitelistedCallers, true);

    wethUsdcLPToken.mint(address(mockRouter), 1000000 ether);
    usdc.mint(address(mockRouter), 1000000 ether);
    weth.mint(address(mockRouter), 1000000 ether);

    adminFacet.setMoneyMarket(address(moneyMarketDiamond));

    // set token config
    ILYFAdminFacet.TokenConfigInput[] memory _inputs = new ILYFAdminFacet.TokenConfigInput[](7);

    _inputs[0] = ILYFAdminFacet.TokenConfigInput({
      token: address(weth),
      tier: LibLYF01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30e18,
      maxCollateral: 100e18,
      maxToleranceExpiredSecond: block.timestamp
    });

    _inputs[1] = ILYFAdminFacet.TokenConfigInput({
      token: address(usdc),
      tier: LibLYF01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 1e24,
      maxCollateral: 10e24,
      maxToleranceExpiredSecond: block.timestamp
    });

    _inputs[2] = ILYFAdminFacet.TokenConfigInput({
      token: address(ibWeth),
      tier: LibLYF01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 0,
      maxBorrow: 1e24,
      maxCollateral: 10e24,
      maxToleranceExpiredSecond: block.timestamp
    });

    _inputs[3] = ILYFAdminFacet.TokenConfigInput({
      token: address(wethUsdcLPToken),
      tier: LibLYF01.AssetTier.LP,
      collateralFactor: 9000,
      borrowingFactor: 0,
      maxBorrow: 0,
      maxCollateral: 10e24,
      maxToleranceExpiredSecond: block.timestamp
    });

    _inputs[4] = ILYFAdminFacet.TokenConfigInput({
      token: address(ibUsdc),
      tier: LibLYF01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 0,
      maxBorrow: 1e24,
      maxCollateral: 10e24,
      maxToleranceExpiredSecond: block.timestamp
    });

    _inputs[5] = ILYFAdminFacet.TokenConfigInput({
      token: address(btc),
      tier: LibLYF01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30e18,
      maxCollateral: 100e18,
      maxToleranceExpiredSecond: block.timestamp
    });

    _inputs[6] = ILYFAdminFacet.TokenConfigInput({
      token: address(ibBtc),
      tier: LibLYF01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30e18,
      maxCollateral: 10e24,
      maxToleranceExpiredSecond: block.timestamp
    });

    adminFacet.setTokenConfigs(_inputs);

    address[] memory _reinvestPath = new address[](2);
    _reinvestPath[0] = address(cake);
    _reinvestPath[1] = address(usdc);

    ILYFAdminFacet.LPConfigInput[] memory lpConfigs = new ILYFAdminFacet.LPConfigInput[](1);
    lpConfigs[0] = ILYFAdminFacet.LPConfigInput({
      lpToken: address(wethUsdcLPToken),
      strategy: address(addStrat),
      masterChef: address(masterChef),
      router: address(mockRouter),
      reinvestPath: _reinvestPath,
      reinvestThreshold: reinvestThreshold,
      rewardToken: address(cake),
      poolId: wethUsdcPoolId
    });
    adminFacet.setLPConfigs(lpConfigs);

    // set oracle for LYF
    mockOracle = new MockAlpacaV2Oracle();
    mockOracle.setTokenPrice(address(weth), 1e18);
    mockOracle.setTokenPrice(address(usdc), 1e18);
    mockOracle.setTokenPrice(address(btc), 10e18);
    mockOracle.setTokenPrice(address(isolateToken), 1e18);
    mockOracle.setLpTokenPrice(address(wethUsdcLPToken), 2e18);

    chainLinkOracle = deployMockChainLinkPriceOracle();

    IAdminFacet(moneyMarketDiamond).setOracle(address(mockOracle));
    IAdminFacet(lyfDiamond).setOracle(address(mockOracle));

    // set debt share indexes
    adminFacet.setDebtShareId(address(weth), address(wethUsdcLPToken), 1);
    adminFacet.setDebtShareId(address(usdc), address(wethUsdcLPToken), 2);

    // set interest model
    adminFacet.setDebtInterestModel(1, address(new MockInterestModel(0.1 ether)));
    adminFacet.setDebtInterestModel(2, address(new MockInterestModel(0.05 ether)));

    adminFacet.setTreasury(treasury);
  }

  function setUpMM() internal {
    IAdminFacet.IbPair[] memory _ibPair = new IAdminFacet.IbPair[](4);
    _ibPair[0] = IAdminFacet.IbPair({ token: address(weth), ibToken: address(ibWeth) });
    _ibPair[1] = IAdminFacet.IbPair({ token: address(usdc), ibToken: address(ibUsdc) });
    _ibPair[2] = IAdminFacet.IbPair({ token: address(btc), ibToken: address(ibBtc) });
    _ibPair[3] = IAdminFacet.IbPair({ token: address(nativeToken), ibToken: address(ibWNative) });
    IAdminFacet(moneyMarketDiamond).setTokenToIbTokens(_ibPair);

    IAdminFacet(moneyMarketDiamond).setNonCollatBorrower(lyfDiamond, true);
    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](3);

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
      token: address(btc),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30e18,
      maxCollateral: 100e18,
      maxToleranceExpiredSecond: block.timestamp
    });

    IAdminFacet(moneyMarketDiamond).setTokenConfigs(_inputs);

    IAdminFacet.NonCollatBorrowLimitInput[] memory _limitInputs = new IAdminFacet.NonCollatBorrowLimitInput[](1);
    _limitInputs[0] = IAdminFacet.NonCollatBorrowLimitInput({ account: lyfDiamond, limit: 1000 ether });

    IAdminFacet(moneyMarketDiamond).setNonCollatBorrowLimitUSDValues(_limitInputs);

    vm.startPrank(EVE);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    usdc.approve(moneyMarketDiamond, type(uint256).max);

    ILendFacet(moneyMarketDiamond).deposit(address(weth), 100 ether);
    ILendFacet(moneyMarketDiamond).deposit(address(usdc), 100 ether);
    vm.stopPrank();
  }
}
