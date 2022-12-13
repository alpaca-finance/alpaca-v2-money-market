// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BaseTest, console } from "../base/BaseTest.sol";

// helper
import { AVDiamondDeployer } from "../helper/AVDiamondDeployer.sol";

// interfaces
import { IAVAdminFacet } from "../../contracts/automated-vault/interfaces/IAVAdminFacet.sol";
import { IAVFarmFacet } from "../../contracts/automated-vault/interfaces/IAVFarmFacet.sol";

abstract contract AV_BaseTest is BaseTest {
  address internal avDiamond;

  // av facets
  IAVAdminFacet internal adminFacet;
  IAVFarmFacet internal farmFacet;

  function setUp() public virtual {
    avDiamond = AVDiamondDeployer.deployPoolDiamond();

    // set av facets
    adminFacet = IAVAdminFacet(avDiamond);
    farmFacet = IAVFarmFacet(avDiamond);

    // approve
    vm.startPrank(ALICE);
    weth.approve(avDiamond, type(uint256).max);
    vm.stopPrank();

    // setup share tokens
    IAVAdminFacet.ShareTokenPairs[] memory shareTokenPairs = new IAVAdminFacet.ShareTokenPairs[](1);
    shareTokenPairs[0] = IAVAdminFacet.ShareTokenPairs({ token: address(weth), shareToken: address(avShareToken) });
    adminFacet.setTokensToShareTokens(shareTokenPairs);
  }
}
