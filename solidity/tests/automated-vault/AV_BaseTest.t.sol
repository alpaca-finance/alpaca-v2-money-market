// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BaseTest, console } from "../base/BaseTest.sol";

// helper
import { AVDiamondDeployer } from "../helper/AVDiamondDeployer.sol";
import { MMDiamondDeployer } from "../helper/MMDiamondDeployer.sol";

// mocks
import { MockLPToken } from "../mocks/MockLPToken.sol";
import { MockRouter } from "../mocks/MockRouter.sol";
import { MockAlpacaV2Oracle } from "../mocks/MockAlpacaV2Oracle.sol";

// contracts
import { AVHandler } from "../../contracts/automated-vault/handlers/AVHandler.sol";

// interfaces
import { IAVAdminFacet } from "../../contracts/automated-vault/interfaces/IAVAdminFacet.sol";
import { IAVTradeFacet } from "../../contracts/automated-vault/interfaces/IAVTradeFacet.sol";
import { IAdminFacet } from "../../contracts/money-market/interfaces/IAdminFacet.sol";

// libraries
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

abstract contract AV_BaseTest is BaseTest {
  address internal avDiamond;
  address internal moneyMarketDiamond;

  // av facets
  IAVAdminFacet internal adminFacet;
  IAVTradeFacet internal tradeFacet;

  function setUp() public virtual {
    avDiamond = AVDiamondDeployer.deployPoolDiamond();
    moneyMarketDiamond = MMDiamondDeployer.deployPoolDiamond(address(nativeToken), address(nativeRelayer));
    setUpMM();

    // set av facets
    adminFacet = IAVAdminFacet(avDiamond);
    tradeFacet = IAVTradeFacet(avDiamond);

    // set MM, todo: should initialize ?
    adminFacet.setMoneyMarket(address(moneyMarketDiamond));

    // approve
    vm.startPrank(ALICE);
    weth.approve(avDiamond, type(uint256).max);
    vm.stopPrank();

    // setup share tokens
    IAVAdminFacet.ShareTokenPairs[] memory shareTokenPairs = new IAVAdminFacet.ShareTokenPairs[](1);
    shareTokenPairs[0] = IAVAdminFacet.ShareTokenPairs({ token: address(weth), shareToken: address(avShareToken) });
    adminFacet.setTokensToShareTokens(shareTokenPairs);

    // setup handler
    MockLPToken wethUsdcLPToken = new MockLPToken("MOCK LP", "MOCK LP", 18, address(weth), address(usdc));
    MockRouter mockRouter = new MockRouter(address(wethUsdcLPToken));

    // mint for router
    wethUsdcLPToken.mint(address(mockRouter), 1000000 ether);

    AVHandler _handler = new AVHandler(address(mockRouter));
    adminFacet.setAVHandler(address(avShareToken), address(_handler));

    // set mock oracle
    MockAlpacaV2Oracle _oracle = new MockAlpacaV2Oracle();
    IAdminFacet(moneyMarketDiamond).setOracle(address(_oracle));
    IAdminFacet(avDiamond).setOracle(address(_oracle));

    // set lp price
    _oracle.setTokenPrice(address(wethUsdcLPToken), 10 ether);
  }

  function setUpMM() internal {
    IAdminFacet.IbPair[] memory _ibPair = new IAdminFacet.IbPair[](2);
    _ibPair[0] = IAdminFacet.IbPair({ token: address(weth), ibToken: address(ibWeth) });
    _ibPair[1] = IAdminFacet.IbPair({ token: address(usdc), ibToken: address(ibUsdc) });
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

    // prepare for borrow
    weth.mint(moneyMarketDiamond, 1000 ether);
    usdc.mint(moneyMarketDiamond, 1000 ether);
  }
}
