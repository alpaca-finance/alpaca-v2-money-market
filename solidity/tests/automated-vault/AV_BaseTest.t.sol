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

// libraries
import { LibAV01 } from "../../contracts/automated-vault/libraries/LibAV01.sol";

// mocks
import { MockAlpacaV2Oracle } from "../mocks/MockAlpacaV2Oracle.sol";
import { MockLPToken } from "../mocks/MockLPToken.sol";

abstract contract AV_BaseTest is BaseTest {
  address internal avDiamond;
  address internal moneyMarketDiamond;

  // av facets
  IAVAdminFacet internal adminFacet;
  IAVTradeFacet internal tradeFacet;

  IAVShareToken internal avShareToken;

  MockLPToken internal wethUsdcLPToken;
  MockAlpacaV2Oracle internal mockOracle;

  function setUp() public virtual {
    avDiamond = AVDiamondDeployer.deployPoolDiamond();
    moneyMarketDiamond = MMDiamondDeployer.deployPoolDiamond(address(nativeToken), address(nativeRelayer));

    // set av facets
    adminFacet = IAVAdminFacet(avDiamond);
    tradeFacet = IAVTradeFacet(avDiamond);

    // approve
    vm.startPrank(ALICE);
    weth.approve(avDiamond, type(uint256).max);
    vm.stopPrank();

    // setup share tokens
    wethUsdcLPToken = new MockLPToken("MOCK LP", "MOCK LP", 18, address(weth), address(usdc));
    avShareToken = IAVShareToken(adminFacet.openVault(address(wethUsdcLPToken), address(usdc), address(weth)));

    // setup token configs
    IAVAdminFacet.TokenConfigInput[] memory tokenConfigs = new IAVAdminFacet.TokenConfigInput[](1);
    tokenConfigs[0] = IAVAdminFacet.TokenConfigInput({
      token: address(weth),
      tier: LibAV01.AssetTier.UNLISTED,
      maxToleranceExpiredSecond: block.timestamp
    });
    adminFacet.setTokenConfigs(tokenConfigs);

    // setup oracle
    mockOracle = new MockAlpacaV2Oracle();
    mockOracle.setTokenPrice(address(weth), 1e18);
    mockOracle.setTokenPrice(address(usdc), 1e18);

    adminFacet.setOracle(address(mockOracle));
    IAdminFacet(moneyMarketDiamond).setOracle(address(mockOracle));
  }
}
