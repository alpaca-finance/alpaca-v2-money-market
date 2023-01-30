// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BaseTest, console } from "../base/BaseTest.sol";

// core
import { LYFDiamond } from "../../contracts/lyf/LYFDiamond.sol";
import { MoneyMarketDiamond } from "../../contracts/money-market/MoneyMarketDiamond.sol";

// contracts
import { InterestBearingToken } from "../../contracts/money-market/InterestBearingToken.sol";

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
import { ILYFViewFacet } from "../../contracts/lyf/interfaces/ILYFViewFacet.sol";
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
  ILYFViewFacet internal viewFacet;

  MockLPToken internal wethUsdcLPToken;
  MockLPToken internal btcUsdcLPToken;
  uint256 internal wethUsdcPoolId;
  uint256 internal btcUsdcPoolId;

  MockChainLinkPriceOracle chainLinkOracle;

  MockRouter internal mockRouter;
  PancakeswapV2Strategy internal addStrat;
  MockMasterChef internal masterChef;
  MockAlpacaV2Oracle internal mockOracle;

  uint256 constant reinvestThreshold = 1e18;

  function setUp() public virtual {
    moneyMarketDiamond = MMDiamondDeployer.deployPoolDiamond(address(wNativeToken), address(wNativeRelayer));
    lyfDiamond = LYFDiamondDeployer.deployPoolDiamond(moneyMarketDiamond);
    setUpMM(moneyMarketDiamond);

    adminFacet = LYFAdminFacet(lyfDiamond);
    collateralFacet = ILYFCollateralFacet(lyfDiamond);
    farmFacet = ILYFFarmFacet(lyfDiamond);
    liquidationFacet = ILYFLiquidationFacet(lyfDiamond);
    ownershipFacet = ILYFOwnershipFacet(lyfDiamond);
    viewFacet = ILYFViewFacet(lyfDiamond);

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
    btc.approve(lyfDiamond, type(uint256).max);
    ibWeth.approve(lyfDiamond, type(uint256).max);
    ibUsdc.approve(lyfDiamond, type(uint256).max);
    vm.stopPrank();

    // DEPLOY MASTERCHEF
    masterChef = new MockMasterChef(address(cake));

    // MASTERCHEF POOLID
    wethUsdcPoolId = 1;
    btcUsdcPoolId = 2;

    // mock LP, Router and Stratgy
    wethUsdcLPToken = new MockLPToken("MOCK WETH-USDC LP", "MOCK LP", 18, address(weth), address(usdc));
    btcUsdcLPToken = new MockLPToken("MOCK BTC-USDC LP", "MOCK LP", 18, address(btc), address(usdc));

    mockRouter = new MockRouter(address(wethUsdcLPToken));

    masterChef.addLendingPool(address(wethUsdcLPToken), wethUsdcPoolId);
    masterChef.addLendingPool(address(btcUsdcLPToken), btcUsdcPoolId);

    addStrat = new PancakeswapV2Strategy(IRouterLike(address(mockRouter)));
    address[] memory stratWhitelistedCallers = new address[](1);
    stratWhitelistedCallers[0] = lyfDiamond;
    addStrat.setWhitelistedCallers(stratWhitelistedCallers, true);

    wethUsdcLPToken.mint(address(mockRouter), 1000000 ether);
    btcUsdcLPToken.mint(address(mockRouter), 1000000 ether);
    usdc.mint(address(mockRouter), 1000000 ether);
    weth.mint(address(mockRouter), 1000000 ether);
    btc.mint(address(mockRouter), 1000000 ether);

    // set token config
    ILYFAdminFacet.TokenConfigInput[] memory _inputs = new ILYFAdminFacet.TokenConfigInput[](9);

    _inputs[0] = ILYFAdminFacet.TokenConfigInput({
      token: address(weth),
      tier: LibLYF01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxCollateral: 100 ether
    });

    _inputs[1] = ILYFAdminFacet.TokenConfigInput({
      token: address(usdc),
      tier: LibLYF01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxCollateral: 100 ether
    });

    _inputs[2] = ILYFAdminFacet.TokenConfigInput({
      token: address(ibWeth),
      tier: LibLYF01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 0,
      maxCollateral: 10e24
    });

    _inputs[3] = ILYFAdminFacet.TokenConfigInput({
      token: address(wethUsdcLPToken),
      tier: LibLYF01.AssetTier.LP,
      collateralFactor: 9000,
      borrowingFactor: 0,
      maxCollateral: 10e24
    });

    _inputs[4] = ILYFAdminFacet.TokenConfigInput({
      token: address(btcUsdcLPToken),
      tier: LibLYF01.AssetTier.LP,
      collateralFactor: 9000,
      borrowingFactor: 0,
      maxCollateral: 10e24
    });

    _inputs[5] = ILYFAdminFacet.TokenConfigInput({
      token: address(ibUsdc),
      tier: LibLYF01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 0,
      maxCollateral: 10e24
    });

    _inputs[6] = ILYFAdminFacet.TokenConfigInput({
      token: address(btc),
      tier: LibLYF01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxCollateral: 100e18
    });

    _inputs[7] = ILYFAdminFacet.TokenConfigInput({
      token: address(ibBtc),
      tier: LibLYF01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxCollateral: 10e24
    });

    _inputs[8] = ILYFAdminFacet.TokenConfigInput({
      token: address(cake),
      tier: LibLYF01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxCollateral: 100e18
    });

    adminFacet.setTokenConfigs(_inputs);

    address[] memory _reinvestPath = new address[](2);
    _reinvestPath[0] = address(cake);
    _reinvestPath[1] = address(usdc);

    ILYFAdminFacet.LPConfigInput[] memory lpConfigs = new ILYFAdminFacet.LPConfigInput[](2);
    lpConfigs[0] = ILYFAdminFacet.LPConfigInput({
      lpToken: address(wethUsdcLPToken),
      strategy: address(addStrat),
      masterChef: address(masterChef),
      router: address(mockRouter),
      reinvestPath: _reinvestPath,
      reinvestThreshold: reinvestThreshold,
      poolId: wethUsdcPoolId,
      rewardToken: address(cake),
      maxLpAmount: 100 ether,
      reinvestTreasuryBountyBps: 1500
    });
    lpConfigs[1] = ILYFAdminFacet.LPConfigInput({
      lpToken: address(btcUsdcLPToken),
      strategy: address(addStrat),
      masterChef: address(masterChef),
      router: address(mockRouter),
      reinvestPath: _reinvestPath,
      reinvestThreshold: reinvestThreshold,
      poolId: btcUsdcPoolId,
      rewardToken: address(cake),
      maxLpAmount: 100 ether,
      reinvestTreasuryBountyBps: 1500
    });
    adminFacet.setLPConfigs(lpConfigs);

    // set oracle for LYF
    mockOracle = new MockAlpacaV2Oracle();
    mockOracle.setTokenPrice(address(weth), 1e18);
    mockOracle.setTokenPrice(address(usdc), 1e18);
    mockOracle.setTokenPrice(address(btc), 10e18);
    mockOracle.setTokenPrice(address(isolateToken), 1e18);
    mockOracle.setLpTokenPrice(address(wethUsdcLPToken), 2e18);
    mockOracle.setLpTokenPrice(address(btcUsdcLPToken), 5e18);

    chainLinkOracle = deployMockChainLinkPriceOracle();

    IAdminFacet(moneyMarketDiamond).setOracle(address(mockOracle));
    IAdminFacet(lyfDiamond).setOracle(address(mockOracle));

    // set debt share indexes
    adminFacet.setDebtPoolId(address(weth), address(wethUsdcLPToken), 1);
    adminFacet.setDebtPoolId(address(usdc), address(wethUsdcLPToken), 2);
    adminFacet.setDebtPoolId(address(btc), address(btcUsdcLPToken), 3);
    adminFacet.setDebtPoolId(address(usdc), address(btcUsdcLPToken), 4);

    // set interest model
    adminFacet.setDebtPoolInterestModel(1, address(new MockInterestModel(0.1 ether)));
    adminFacet.setDebtPoolInterestModel(2, address(new MockInterestModel(0.05 ether)));
    adminFacet.setDebtPoolInterestModel(3, address(new MockInterestModel(0.05 ether)));
    adminFacet.setDebtPoolInterestModel(4, address(new MockInterestModel(0.05 ether)));

    adminFacet.setTreasury(treasury);

    // set max num of tokens
    adminFacet.setMaxNumOfToken(3, 3);

    adminFacet.setMinDebtSize(0.01 ether);
  }

  function setUpMM(address _moneyMarketDiamond) internal {
    IAdminFacet mmAdminFacet = IAdminFacet(_moneyMarketDiamond);

    // set ib token implementation
    // warning: this one should set before open market
    mmAdminFacet.setIbTokenImplementation(address(new InterestBearingToken()));

    address _ibWeth = mmAdminFacet.openMarket(address(weth));
    address _ibUsdc = mmAdminFacet.openMarket(address(usdc));
    address _ibBtc = mmAdminFacet.openMarket(address(btc));
    address _ibNativeToken = mmAdminFacet.openMarket(address(wNativeToken));

    ibWeth = InterestBearingToken(_ibWeth);
    ibUsdc = InterestBearingToken(_ibUsdc);
    ibBtc = InterestBearingToken(_ibBtc);
    ibWNative = InterestBearingToken(_ibNativeToken);

    mmAdminFacet.setNonCollatBorrowerOk(lyfDiamond, true);
    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](4);

    _inputs[0] = IAdminFacet.TokenConfigInput({
      token: address(weth),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 10000 ether,
      maxCollateral: 10000 ether
    });

    _inputs[1] = IAdminFacet.TokenConfigInput({
      token: address(usdc),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 10000 ether,
      maxCollateral: 10000 ether
    });

    _inputs[2] = IAdminFacet.TokenConfigInput({
      token: address(btc),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 100e18,
      maxCollateral: 100e18
    });

    _inputs[3] = IAdminFacet.TokenConfigInput({
      token: address(cake),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 100e18,
      maxCollateral: 100e18
    });

    mmAdminFacet.setTokenConfigs(_inputs);

    IAdminFacet.TokenBorrowLimitInput[] memory _tokenBorrowLimitInputs = new IAdminFacet.TokenBorrowLimitInput[](4);
    _tokenBorrowLimitInputs[0] = IAdminFacet.TokenBorrowLimitInput({
      token: address(weth),
      maxTokenBorrow: type(uint256).max
    });
    _tokenBorrowLimitInputs[1] = IAdminFacet.TokenBorrowLimitInput({
      token: address(usdc),
      maxTokenBorrow: type(uint256).max
    });
    _tokenBorrowLimitInputs[2] = IAdminFacet.TokenBorrowLimitInput({
      token: address(btc),
      maxTokenBorrow: type(uint256).max
    });
    _tokenBorrowLimitInputs[3] = IAdminFacet.TokenBorrowLimitInput({
      token: address(cake),
      maxTokenBorrow: type(uint256).max
    });

    IAdminFacet.ProtocolConfigInput[] memory _protocolConfigInputs = new IAdminFacet.ProtocolConfigInput[](1);
    _protocolConfigInputs[0] = IAdminFacet.ProtocolConfigInput({
      account: lyfDiamond,
      tokenBorrowLimit: _tokenBorrowLimitInputs,
      borrowLimitUSDValue: type(uint256).max
    });

    mmAdminFacet.setProtocolConfigs(_protocolConfigInputs);

    vm.startPrank(EVE);

    weth.approve(moneyMarketDiamond, type(uint256).max);
    usdc.approve(moneyMarketDiamond, type(uint256).max);
    btc.approve(moneyMarketDiamond, type(uint256).max);

    // DON'T change these value. Some test cases are tied to deposit balances.
    ILendFacet(moneyMarketDiamond).deposit(address(weth), 100 ether);
    ILendFacet(moneyMarketDiamond).deposit(address(usdc), 100 ether);
    ILendFacet(moneyMarketDiamond).deposit(address(btc), 100 ether);

    vm.stopPrank();

    // set max num of tokens
    mmAdminFacet.setMaxNumOfToken(3, 3, 3);
  }
}
