// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BaseTest, console } from "../base/BaseTest.sol";

// helper
import { AVDiamondDeployer } from "../helper/AVDiamondDeployer.sol";

// interfaces
import { IAVAdminFacet } from "../../contracts/automated-vault/interfaces/IAVAdminFacet.sol";

abstract contract AV_BaseTest is BaseTest {
  address internal avDiamond;

  // av facets
  IAVAdminFacet internal adminFacet;

  function setUp() public virtual {
    avDiamond = AVDiamondDeployer.deployPoolDiamond();

    // set av facets
    adminFacet = IAVAdminFacet(avDiamond);
  }
}
