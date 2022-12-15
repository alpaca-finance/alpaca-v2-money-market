// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BaseTest, console } from "../base/BaseTest.sol";

// helper
import { AVDiamondDeployer } from "../helper/AVDiamondDeployer.sol";
import { MMDiamondDeployer } from "../helper/MMDiamondDeployer.sol";

// interfaces
import { IAVAdminFacet } from "../../contracts/automated-vault/interfaces/IAVAdminFacet.sol";
import { IAVTradeFacet } from "../../contracts/automated-vault/interfaces/IAVTradeFacet.sol";
import { IAVShareToken } from "../../contracts/automated-vault/interfaces/IAVShareToken.sol";
import { IAdminFacet } from "../../contracts/money-market/interfaces/IAdminFacet.sol";
import { ILendFacet } from "../../contracts/money-market/interfaces/ILendFacet.sol";

// libraries
import { LibAV01 } from "../../contracts/automated-vault/libraries/LibAV01.sol";
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// mocks
import { MockAlpacaV2Oracle } from "../mocks/MockAlpacaV2Oracle.sol";
import { MockLPToken } from "../mocks/MockLPToken.sol";

abstract contract AV_BaseTest is BaseTest {
  address internal avDiamond;
  address internal moneyMarketDiamond;

  // av facets
  IAVAdminFacet internal adminFacet;
  IAVTradeFacet internal tradeFacet;

  address internal treasury;

  IAVShareToken internal avShareToken;

  MockLPToken internal wethUsdcLPToken;
  MockAlpacaV2Oracle internal mockOracle;

  function setUp() public virtual {
    avDiamond = AVDiamondDeployer.deployPoolDiamond();
    moneyMarketDiamond = MMDiamondDeployer.deployPoolDiamond(address(nativeToken), address(nativeRelayer));
    setUpMM();

    // set av facets
    adminFacet = IAVAdminFacet(avDiamond);
    tradeFacet = IAVTradeFacet(avDiamond);

    adminFacet.setMoneyMarket(moneyMarketDiamond);

    // setup share tokens
    wethUsdcLPToken = new MockLPToken("MOCK LP", "MOCK LP", 18, address(weth), address(usdc));
    avShareToken = IAVShareToken(adminFacet.openVault(address(wethUsdcLPToken), address(usdc), address(weth), 3, 0));

    // approve
    vm.startPrank(ALICE);
    weth.approve(avDiamond, type(uint256).max);
    usdc.approve(avDiamond, type(uint256).max);
    vm.stopPrank();

    // setup token configs
    IAVAdminFacet.TokenConfigInput[] memory tokenConfigs = new IAVAdminFacet.TokenConfigInput[](2);
    tokenConfigs[0] = IAVAdminFacet.TokenConfigInput({
      token: address(weth),
      tier: LibAV01.AssetTier.TOKEN,
      maxToleranceExpiredSecond: block.timestamp
    });
    tokenConfigs[1] = IAVAdminFacet.TokenConfigInput({
      token: address(usdc),
      tier: LibAV01.AssetTier.TOKEN,
      maxToleranceExpiredSecond: block.timestamp
    });
    adminFacet.setTokenConfigs(tokenConfigs);

    // setup oracle
    mockOracle = new MockAlpacaV2Oracle();
    mockOracle.setTokenPrice(address(weth), 1e18);
    mockOracle.setTokenPrice(address(usdc), 1e18);

    adminFacet.setOracle(address(mockOracle));
    IAdminFacet(moneyMarketDiamond).setOracle(address(mockOracle));

    mockOracle.setTokenPrice(address(weth), 1e18);
    mockOracle.setTokenPrice(address(usdc), 1e18);
    mockOracle.setTokenPrice(address(wethUsdcLPToken), 2e18);

    // set treasury
    treasury = address(this);
    adminFacet.setTreasury(treasury);
  }

  function setUpMM() internal {
    IAdminFacet.IbPair[] memory _ibPair = new IAdminFacet.IbPair[](4);
    _ibPair[0] = IAdminFacet.IbPair({ token: address(weth), ibToken: address(ibWeth) });
    _ibPair[1] = IAdminFacet.IbPair({ token: address(usdc), ibToken: address(ibUsdc) });
    _ibPair[2] = IAdminFacet.IbPair({ token: address(btc), ibToken: address(ibBtc) });
    _ibPair[3] = IAdminFacet.IbPair({ token: address(nativeToken), ibToken: address(ibWNative) });
    IAdminFacet(moneyMarketDiamond).setTokenToIbTokens(_ibPair);

    IAdminFacet(moneyMarketDiamond).setNonCollatBorrower(avDiamond, true);
    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](2);

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
    _limitInputs[0] = IAdminFacet.NonCollatBorrowLimitInput({ account: avDiamond, limit: 1000 ether });

    IAdminFacet(moneyMarketDiamond).setNonCollatBorrowLimitUSDValues(_limitInputs);

    vm.startPrank(EVE);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    usdc.approve(moneyMarketDiamond, type(uint256).max);

    ILendFacet(moneyMarketDiamond).deposit(address(weth), 50 ether);
    ILendFacet(moneyMarketDiamond).deposit(address(usdc), 20 ether);
    vm.stopPrank();
  }
}
