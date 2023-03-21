// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseTest, console } from "../base/BaseTest.sol";

// core
import { LYFDiamond } from "../../contracts/lyf/LYFDiamond.sol";

// contracts
import { InterestBearingToken } from "../../contracts/money-market/InterestBearingToken.sol";
import { DebtToken } from "../../contracts/money-market/DebtToken.sol";

// facets
import { LYFDiamondCutFacet, ILYFDiamondCut } from "../../contracts/lyf/facets/LYFDiamondCutFacet.sol";
import { LYFDiamondLoupeFacet } from "../../contracts/lyf/facets/LYFDiamondLoupeFacet.sol";
import { LYFAdminFacet } from "../../contracts/lyf/facets/LYFAdminFacet.sol";
import { LYFCollateralFacet } from "../../contracts/lyf/facets/LYFCollateralFacet.sol";
import { LYFFarmFacet } from "../../contracts/lyf/facets/LYFFarmFacet.sol";

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
import { LibLYFConstant } from "../../contracts/lyf/libraries/LibLYFConstant.sol";

// peripherals
import { PancakeswapV2Strategy } from "../../contracts/lyf/strats/PancakeswapV2Strategy.sol";
import { LibConstant } from "../../contracts/money-market/libraries/LibConstant.sol";

// helper
import { LYFDiamondDeployer } from "../helper/LYFDiamondDeployer.sol";
import { TestHelper } from "../helper/TestHelper.sol";
import { LibMoneyMarketDeployment } from "../../scripts/deployments/libraries/LibMoneyMarketDeployment.sol";

// oracle
import { OracleMedianizer } from "../../contracts/oracle/OracleMedianizer.sol";

abstract contract LYF_BaseTest is BaseTest {
  address internal lyfDiamond;
  address internal moneyMarketDiamond;
  address internal liquidationTreasury = address(888);
  address internal revenueTreasury = address(889);
  address internal liquidator = address(666);

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
    (moneyMarketDiamond, ) = LibMoneyMarketDeployment.deployMoneyMarketDiamond(address(miniFL));

    (lyfDiamond, ) = LYFDiamondDeployer.deployLYFDiamond(moneyMarketDiamond);
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
    usdc.mint(address(mockRouter), normalizeEther(1000000 ether, usdcDecimal));
    weth.mint(address(mockRouter), 1000000 ether);
    btc.mint(address(mockRouter), 1000000 ether);

    // set token config
    ILYFAdminFacet.TokenConfigInput[] memory _inputs = new ILYFAdminFacet.TokenConfigInput[](9);

    _inputs[0] = ILYFAdminFacet.TokenConfigInput({
      token: address(weth),
      tier: LibLYFConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxCollateral: 100 ether
    });

    _inputs[1] = ILYFAdminFacet.TokenConfigInput({
      token: address(usdc),
      tier: LibLYFConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxCollateral: normalizeEther(100 ether, usdcDecimal)
    });

    _inputs[2] = ILYFAdminFacet.TokenConfigInput({
      token: address(ibWeth),
      tier: LibLYFConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 1,
      maxCollateral: 10e24
    });

    _inputs[3] = ILYFAdminFacet.TokenConfigInput({
      token: address(wethUsdcLPToken),
      tier: LibLYFConstant.AssetTier.LP,
      collateralFactor: 9000,
      borrowingFactor: 1,
      maxCollateral: 10e24
    });

    _inputs[4] = ILYFAdminFacet.TokenConfigInput({
      token: address(btcUsdcLPToken),
      tier: LibLYFConstant.AssetTier.LP,
      collateralFactor: 9000,
      borrowingFactor: 1,
      maxCollateral: 10e24
    });

    _inputs[5] = ILYFAdminFacet.TokenConfigInput({
      token: address(ibUsdc),
      tier: LibLYFConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 1,
      maxCollateral: normalizeEther(10e24, usdcDecimal)
    });

    _inputs[6] = ILYFAdminFacet.TokenConfigInput({
      token: address(btc),
      tier: LibLYFConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxCollateral: 100e18
    });

    _inputs[7] = ILYFAdminFacet.TokenConfigInput({
      token: address(ibBtc),
      tier: LibLYFConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxCollateral: 10e24
    });

    _inputs[8] = ILYFAdminFacet.TokenConfigInput({
      token: address(cake),
      tier: LibLYFConstant.AssetTier.COLLATERAL,
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

    // set reward conversion configs
    address[] memory _rewardConversionPath = new address[](2);
    _rewardConversionPath[0] = address(cake);
    _rewardConversionPath[1] = address(cake);

    ILYFAdminFacet.SetRewardConversionConfigInput[]
      memory _rewardConversionConfigInputs = new ILYFAdminFacet.SetRewardConversionConfigInput[](1);
    _rewardConversionConfigInputs[0] = ILYFAdminFacet.SetRewardConversionConfigInput({
      rewardToken: address(cake),
      router: address(mockRouter),
      path: _rewardConversionPath
    });

    adminFacet.setRewardConversionConfigs(_rewardConversionConfigInputs);

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
    adminFacet.setDebtPoolInterestModel(1, address(new MockInterestModel(normalizeEther(0.1 ether, 18)))); // lptoken decimal
    adminFacet.setDebtPoolInterestModel(2, address(new MockInterestModel(normalizeEther(0.05 ether, 18)))); // lptoken decimal
    adminFacet.setDebtPoolInterestModel(3, address(new MockInterestModel(normalizeEther(0.05 ether, 18)))); // lptoken decimal
    adminFacet.setDebtPoolInterestModel(4, address(new MockInterestModel(normalizeEther(0.05 ether, 18)))); // lptoken decimal

    adminFacet.setLiquidationTreasury(liquidationTreasury);
    adminFacet.setRevenueTreasury(revenueTreasury);

    // set max num of tokens
    adminFacet.setMaxNumOfToken(3, 3);

    adminFacet.setMinDebtSize(normalizeEther(0.01 ether, usdDecimal));

    // set account manager to allow interactions
    address[] memory _accountManagers = new address[](1);
    _accountManagers[0] = lyfDiamond;
    mmWhitelistAccountManagers(moneyMarketDiamond, _accountManagers);
  }

  function setUpMM(address _moneyMarketDiamond) internal {
    IAdminFacet mmAdminFacet = IAdminFacet(_moneyMarketDiamond);

    // set ibToken and debtToken implementation
    // warning: this one should set before open market
    mmAdminFacet.setIbTokenImplementation(address(new InterestBearingToken()));
    mmAdminFacet.setDebtTokenImplementation(address(new DebtToken()));

    address[] memory _whitelistedCallers = new address[](1);
    _whitelistedCallers[0] = moneyMarketDiamond;
    miniFL.setWhitelistedCallers(_whitelistedCallers, true);

    ibWeth = TestHelper.openMarketWithDefaultTokenConfig(_moneyMarketDiamond, address(weth));
    ibUsdc = TestHelper.openMarketWithDefaultTokenConfig(_moneyMarketDiamond, address(usdc));
    ibBtc = TestHelper.openMarketWithDefaultTokenConfig(_moneyMarketDiamond, address(btc));
    ibWNative = TestHelper.openMarketWithDefaultTokenConfig(_moneyMarketDiamond, address(wNativeToken));

    ibWethDecimal = ibWeth.decimals();
    ibUsdcDecimal = ibUsdc.decimals();
    ibBtcDecimal = ibBtc.decimals();
    ibWNativeDecimal = ibWNative.decimals();

    mmAdminFacet.setNonCollatBorrowerOk(lyfDiamond, true);

    address[] memory _tokens = new address[](4);
    _tokens[0] = address(weth);
    _tokens[1] = address(usdc);
    _tokens[2] = address(btc);
    _tokens[3] = address(cake);

    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](4);
    _inputs[0] = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: normalizeEther(10000 ether, wethDecimal),
      maxCollateral: normalizeEther(10000 ether, wethDecimal)
    });
    _inputs[1] = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: normalizeEther(10000 ether, usdcDecimal),
      maxCollateral: normalizeEther(10000 ether, usdcDecimal)
    });
    _inputs[2] = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: normalizeEther(100 ether, btcDecimal),
      maxCollateral: normalizeEther(100 ether, btcDecimal)
    });
    _inputs[3] = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: normalizeEther(100 ether, cakeDecimal),
      maxCollateral: normalizeEther(100 ether, cakeDecimal)
    });

    mmAdminFacet.setTokenConfigs(_tokens, _inputs);

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
      borrowingPowerLimit: type(uint256).max
    });

    mmAdminFacet.setProtocolConfigs(_protocolConfigInputs);

    // set max num of tokens
    mmAdminFacet.setMaxNumOfToken(3, 3, 3);

    // set account manager to allow interactions
    address[] memory _accountManagers = new address[](3);
    _accountManagers[0] = ALICE;
    _accountManagers[1] = BOB;
    _accountManagers[2] = EVE;

    mmWhitelistAccountManagers(moneyMarketDiamond, _accountManagers);

    vm.startPrank(EVE);

    weth.approve(moneyMarketDiamond, type(uint256).max);
    usdc.approve(moneyMarketDiamond, type(uint256).max);
    btc.approve(moneyMarketDiamond, type(uint256).max);

    // DON'T change these value. Some test cases are tied to deposit balances.
    ILendFacet(moneyMarketDiamond).deposit(EVE, address(weth), normalizeEther(100 ether, wethDecimal));
    ILendFacet(moneyMarketDiamond).deposit(EVE, address(usdc), normalizeEther(100 ether, usdcDecimal));
    ILendFacet(moneyMarketDiamond).deposit(EVE, address(btc), normalizeEther(100 ether, btcDecimal));

    vm.stopPrank();
  }

  function mmWhitelistAccountManagers(address _moneyMarketDiamond, address[] memory _list) internal {
    IAdminFacet mmAdminFacet = IAdminFacet(_moneyMarketDiamond);

    mmAdminFacet.setAccountManagersOk(_list, true);
  }
}
