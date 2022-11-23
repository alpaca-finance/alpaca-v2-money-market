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
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPancakeRouter02 } from "../../contracts/lyf/interfaces/IPancakeRouter02.sol";
import { IAdminFacet } from "../../contracts/money-market/interfaces/IAdminFacet.sol";
import { ILendFacet } from "../../contracts/money-market/interfaces/ILendFacet.sol";
import { IPriceOracle } from "../../contracts/oracle/interfaces/IPriceOracle.sol";

// mocks
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockLPToken } from "../mocks/MockLPToken.sol";
import { MockChainLinkPriceOracle } from "../mocks/MockChainLinkPriceOracle.sol";
import { MockRouter } from "../mocks/MockRouter.sol";

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

  LYFAdminFacet internal adminFacet;
  ILYFCollateralFacet internal collateralFacet;
  ILYFFarmFacet internal farmFacet;

  MockLPToken internal wethUsdcLPToken;

  MockChainLinkPriceOracle chainLinkOracle;

  MockRouter internal mockRouter;
  PancakeswapV2Strategy internal addStrat;

  function setUp() public virtual {
    lyfDiamond = LYFDiamondDeployer.deployPoolDiamond();
    moneyMarketDiamond = MMDiamondDeployer.deployPoolDiamond(address(nativeToken), address(nativeRelayer));
    setUpMM();

    adminFacet = LYFAdminFacet(lyfDiamond);
    collateralFacet = ILYFCollateralFacet(lyfDiamond);
    farmFacet = ILYFFarmFacet(lyfDiamond);

    vm.startPrank(ALICE);
    weth.approve(lyfDiamond, type(uint256).max);
    usdc.approve(lyfDiamond, type(uint256).max);
    vm.stopPrank();

    vm.startPrank(BOB);
    weth.approve(lyfDiamond, type(uint256).max);
    usdc.approve(lyfDiamond, type(uint256).max);
    vm.stopPrank();

    // mock LP, Router and Stratgy
    wethUsdcLPToken = new MockLPToken("MOCK LP", "MOCK LP", 18, address(weth), address(usdc));

    mockRouter = new MockRouter(address(wethUsdcLPToken));

    addStrat = new PancakeswapV2Strategy(IPancakeRouter02(address(mockRouter)));

    wethUsdcLPToken.mint(address(mockRouter), 1000000 ether);

    adminFacet.setMoneyMarket(address(moneyMarketDiamond));

    // set token config
    ILYFAdminFacet.TokenConfigInput[] memory _inputs = new ILYFAdminFacet.TokenConfigInput[](4);

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

    adminFacet.setTokenConfigs(_inputs);

    // set oracle for LYF
    oracleMedianizer = deployOracleMedianizer();
    oracleMedianizer.transferOwnership(DEPLOYER);

    alpacaV2Oracle = deployAlpacaV2Oracle(address(oracleMedianizer));
    chainLinkOracle = deployMockChainLinkPriceOracle();

    setUpOracle(oracleMedianizer, chainLinkOracle);

    IAdminFacet(moneyMarketDiamond).setOracle(address(chainLinkOracle));
    IAdminFacet(lyfDiamond).setOracle(address(alpacaV2Oracle));
  }

  function setUpMM() internal {
    IAdminFacet.IbPair[] memory _ibPair = new IAdminFacet.IbPair[](4);
    _ibPair[0] = IAdminFacet.IbPair({ token: address(weth), ibToken: address(ibWeth) });
    _ibPair[1] = IAdminFacet.IbPair({ token: address(usdc), ibToken: address(ibUsdc) });
    _ibPair[2] = IAdminFacet.IbPair({ token: address(btc), ibToken: address(ibBtc) });
    _ibPair[3] = IAdminFacet.IbPair({ token: address(nativeToken), ibToken: address(ibWNative) });
    IAdminFacet(moneyMarketDiamond).setTokenToIbTokens(_ibPair);

    IAdminFacet(moneyMarketDiamond).setNonCollatBorrower(lyfDiamond, true);

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

    IAdminFacet(moneyMarketDiamond).setTokenConfigs(_inputs);

    IAdminFacet.NonCollatBorrowLimitInput[] memory _limitInputs = new IAdminFacet.NonCollatBorrowLimitInput[](1);
    _limitInputs[0] = IAdminFacet.NonCollatBorrowLimitInput({ account: lyfDiamond, limit: 1000 ether });

    IAdminFacet(moneyMarketDiamond).setNonCollatBorrowLimitUSDValues(_limitInputs);

    vm.startPrank(EVE);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    usdc.approve(moneyMarketDiamond, type(uint256).max);

    ILendFacet(moneyMarketDiamond).deposit(address(weth), 50 ether);
    ILendFacet(moneyMarketDiamond).deposit(address(usdc), 20 ether);
    vm.stopPrank();
  }

  function setUpOracle(OracleMedianizer _medianizer, MockChainLinkPriceOracle _oracle) internal {
    vm.startPrank(DEPLOYER);
    _oracle.add(address(weth), address(usd), 1 ether, block.timestamp);
    _oracle.add(address(usdc), address(usd), 1 ether, block.timestamp);
    _oracle.add(address(isolateToken), address(usd), 1 ether, block.timestamp);
    _oracle.add(address(wethUsdcLPToken), address(usd), 2 ether, block.timestamp);

    IPriceOracle[] memory inputs = new IPriceOracle[](1);
    inputs[0] = IPriceOracle(_oracle);

    _medianizer.setPrimarySources(address(weth), address(usd), 1 ether, block.timestamp, inputs);
    _medianizer.setPrimarySources(address(usdc), address(usd), 1 ether, block.timestamp, inputs);
    _medianizer.setPrimarySources(address(isolateToken), address(usd), 1 ether, block.timestamp, inputs);
    _medianizer.setPrimarySources(address(wethUsdcLPToken), address(usd), 1 ether, block.timestamp, inputs);
    vm.stopPrank();
  }
}
