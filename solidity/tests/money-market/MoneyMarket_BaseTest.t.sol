// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseTest, console } from "../base/BaseTest.sol";

// core
import { InterestBearingToken } from "../../contracts/money-market/InterestBearingToken.sol";
import { DebtToken } from "../../contracts/money-market/DebtToken.sol";

// interfaces
import { ICollateralFacet } from "../../contracts/money-market/interfaces/ICollateralFacet.sol";
import { IViewFacet } from "../../contracts/money-market/interfaces/IViewFacet.sol";
import { ILendFacet } from "../../contracts/money-market/interfaces/ILendFacet.sol";
import { IAdminFacet } from "../../contracts/money-market/interfaces/IAdminFacet.sol";
import { IBorrowFacet } from "../../contracts/money-market/interfaces/IBorrowFacet.sol";
import { INonCollatBorrowFacet } from "../../contracts/money-market/interfaces/INonCollatBorrowFacet.sol";
import { ILiquidationFacet } from "../../contracts/money-market/interfaces/ILiquidationFacet.sol";
import { IMMOwnershipFacet } from "../../contracts/money-market/interfaces/IMMOwnershipFacet.sol";
import { IMoneyMarketAccountManager } from "../../contracts/interfaces/IMoneyMarketAccountManager.sol";
import { IERC20 } from "../../contracts/money-market/interfaces/IERC20.sol";

// mocks
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockChainLinkPriceOracle } from "../mocks/MockChainLinkPriceOracle.sol";
import { MockAlpacaV2Oracle } from "../mocks/MockAlpacaV2Oracle.sol";

// libs
import { LibConstant } from "../../contracts/money-market/libraries/LibConstant.sol";
import { LibMoneyMarketDeployment } from "../../scripts/deployments/libraries/LibMoneyMarketDeployment.sol";

// router
import { MoneyMarketAccountManager } from "../../contracts/account-manager/MoneyMarketAccountManager.sol";

abstract contract MoneyMarket_BaseTest is BaseTest {
  address internal moneyMarketDiamond;
  address internal liquidationTreasury = address(666);
  address internal liquidator = address(667);

  IViewFacet internal viewFacet;
  IAdminFacet internal adminFacet;
  ILendFacet internal lendFacet;
  ICollateralFacet internal collateralFacet;
  IBorrowFacet internal borrowFacet;
  INonCollatBorrowFacet internal nonCollatBorrowFacet;
  ILiquidationFacet internal liquidationFacet;
  IMMOwnershipFacet internal MMOwnershipFacet;

  MockAlpacaV2Oracle internal mockOracle;

  IMoneyMarketAccountManager internal accountManager;

  function setUp() public virtual {
    (moneyMarketDiamond, ) = LibMoneyMarketDeployment.deployMoneyMarketDiamond(address(miniFL));

    viewFacet = IViewFacet(moneyMarketDiamond);
    lendFacet = ILendFacet(moneyMarketDiamond);
    collateralFacet = ICollateralFacet(moneyMarketDiamond);
    adminFacet = IAdminFacet(moneyMarketDiamond);
    borrowFacet = IBorrowFacet(moneyMarketDiamond);
    nonCollatBorrowFacet = INonCollatBorrowFacet(moneyMarketDiamond);
    liquidationFacet = ILiquidationFacet(moneyMarketDiamond);
    MMOwnershipFacet = IMMOwnershipFacet(moneyMarketDiamond);

    address[] memory _whitelistedCallers = new address[](1);
    _whitelistedCallers[0] = moneyMarketDiamond;
    miniFL.setWhitelistedCallers(_whitelistedCallers, true);

    // set ibToken and debtToken implementation
    // warning: this one should set before open market
    adminFacet.setIbTokenImplementation(address(new InterestBearingToken()));
    adminFacet.setDebtTokenImplementation(address(new DebtToken()));

    IAdminFacet.TokenConfigInput memory _wethTokenConfigInput = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30 ether,
      maxCollateral: 100 ether
    });
    ibWeth = InterestBearingToken(adminFacet.openMarket(address(weth), _wethTokenConfigInput, _wethTokenConfigInput));

    IAdminFacet.TokenConfigInput memory _usdcTokenConfigInput = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: normalizeEther(100 ether, 6),
      maxCollateral: normalizeEther(100 ether, 6)
    });
    ibUsdc = InterestBearingToken(adminFacet.openMarket(address(usdc), _usdcTokenConfigInput, _usdcTokenConfigInput));

    IAdminFacet.TokenConfigInput memory _btcTokenConfigInput = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30 ether,
      maxCollateral: 100 ether
    });
    ibBtc = InterestBearingToken(adminFacet.openMarket(address(btc), _btcTokenConfigInput, _btcTokenConfigInput));

    IAdminFacet.TokenConfigInput memory _wNativeTokenConfigInput = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30 ether,
      maxCollateral: 100 ether
    });
    ibWNative = InterestBearingToken(
      adminFacet.openMarket(address(wNativeToken), _wNativeTokenConfigInput, _wNativeTokenConfigInput)
    );

    IAdminFacet.TokenConfigInput memory _isolateTokenTokenConfigInput = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.ISOLATE,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30 ether,
      maxCollateral: 100 ether
    });
    ibIsolateToken = InterestBearingToken(
      adminFacet.openMarket(address(isolateToken), _isolateTokenTokenConfigInput, _isolateTokenTokenConfigInput)
    );

    IAdminFacet.TokenConfigInput memory _cakeTokenConfigInput = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30 ether,
      maxCollateral: 100 ether
    });
    adminFacet.openMarket(address(cake), _cakeTokenConfigInput, _cakeTokenConfigInput);

    // set account manager to allow interactions
    accountManager = IMoneyMarketAccountManager(
      deployMoneyMarketAccountManager(moneyMarketDiamond, address(wNativeToken), address(wNativeRelayer))
    );

    address[] memory _accountManagers = new address[](1);
    _accountManagers[0] = address(accountManager);

    // Need this for AM to be able to interact with MM
    adminFacet.setAccountManagersOk(_accountManagers, true);
    // Need this for depositAndStake
    miniFL.setWhitelistedCallers(_accountManagers, true);

    ibWethDecimal = ibWeth.decimals();
    ibUsdcDecimal = ibUsdc.decimals();
    ibBtcDecimal = ibBtc.decimals();
    ibWNativeDecimal = ibWNative.decimals();
    ibIsolateTokenDecimal = ibIsolateToken.decimals();

    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    btc.approve(moneyMarketDiamond, type(uint256).max);
    usdc.approve(moneyMarketDiamond, type(uint256).max);
    isolateToken.approve(moneyMarketDiamond, type(uint256).max);
    ibWeth.approve(moneyMarketDiamond, type(uint256).max);
    cake.approve(moneyMarketDiamond, type(uint256).max);

    weth.approve(address(accountManager), type(uint256).max);
    btc.approve(address(accountManager), type(uint256).max);
    usdc.approve(address(accountManager), type(uint256).max);
    isolateToken.approve(address(accountManager), type(uint256).max);
    ibWeth.approve(address(accountManager), type(uint256).max);
    ibUsdc.approve(address(accountManager), type(uint256).max);
    cake.approve(address(accountManager), type(uint256).max);
    ibWNative.approve(address(accountManager), type(uint256).max);
    vm.stopPrank();

    vm.startPrank(BOB);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    btc.approve(moneyMarketDiamond, type(uint256).max);
    usdc.approve(moneyMarketDiamond, type(uint256).max);
    isolateToken.approve(moneyMarketDiamond, type(uint256).max);

    weth.approve(address(accountManager), type(uint256).max);
    btc.approve(address(accountManager), type(uint256).max);
    usdc.approve(address(accountManager), type(uint256).max);
    isolateToken.approve(address(accountManager), type(uint256).max);
    ibWeth.approve(address(accountManager), type(uint256).max);
    vm.stopPrank();

    IAdminFacet.TokenBorrowLimitInput[] memory _tokenBorrowLimitInputs = new IAdminFacet.TokenBorrowLimitInput[](4);
    _tokenBorrowLimitInputs[0] = IAdminFacet.TokenBorrowLimitInput({
      token: address(weth),
      maxTokenBorrow: normalizeEther(30 ether, wethDecimal)
    });
    _tokenBorrowLimitInputs[1] = IAdminFacet.TokenBorrowLimitInput({
      token: address(usdc),
      maxTokenBorrow: normalizeEther(30 ether, usdcDecimal)
    });
    _tokenBorrowLimitInputs[2] = IAdminFacet.TokenBorrowLimitInput({
      token: address(btc),
      maxTokenBorrow: normalizeEther(30 ether, btcDecimal)
    });
    _tokenBorrowLimitInputs[3] = IAdminFacet.TokenBorrowLimitInput({
      token: address(cake),
      maxTokenBorrow: normalizeEther(30 ether, cakeDecimal)
    });

    IAdminFacet.ProtocolConfigInput[] memory _protocolConfigInputs = new IAdminFacet.ProtocolConfigInput[](2);
    _protocolConfigInputs[0] = IAdminFacet.ProtocolConfigInput({
      account: ALICE,
      tokenBorrowLimit: _tokenBorrowLimitInputs,
      borrowingPowerLimit: type(uint256).max
    });
    _protocolConfigInputs[1] = IAdminFacet.ProtocolConfigInput({
      account: BOB,
      tokenBorrowLimit: _tokenBorrowLimitInputs,
      borrowingPowerLimit: type(uint256).max
    });

    adminFacet.setProtocolConfigs(_protocolConfigInputs);

    //set oracle
    mockOracle = new MockAlpacaV2Oracle();
    mockOracle.setTokenPrice(address(weth), normalizeEther(1 ether, usdDecimal));
    mockOracle.setTokenPrice(address(usdc), normalizeEther(1 ether, usdDecimal));
    mockOracle.setTokenPrice(address(cake), normalizeEther(1 ether, usdDecimal));
    mockOracle.setTokenPrice(address(isolateToken), normalizeEther(1 ether, usdDecimal));
    mockOracle.setTokenPrice(address(btc), normalizeEther(10 ether, usdDecimal));

    adminFacet.setOracle(address(mockOracle));

    // set repurchases ok
    address[] memory _repurchasers = new address[](2);
    _repurchasers[0] = BOB;
    _repurchasers[1] = ALICE;
    adminFacet.setRepurchasersOk(_repurchasers, true);

    adminFacet.setLiquidationTreasury(liquidationTreasury);

    // adminFacet.setFees(_newLendingFeeBps, _newRepurchaseFeeBps, _newLiquidationFeeBps, _newLiquidationRewardBps);
    // _newLiquidationRewardBps = 5000 => 50% of fee goes to liquidator
    adminFacet.setFees(0, 100, 100, 5000);

    // set liquidation params: maxLiquidate 50%, liquidationThreshold 111.11%
    adminFacet.setLiquidationParams(5000, 11111);

    // set max num of token
    adminFacet.setMaxNumOfToken(3, 3, 3);

    // set minimum debt required to borrow
    adminFacet.setMinDebtSize(normalizeEther(0.1 ether, usdDecimal));
  }
}
