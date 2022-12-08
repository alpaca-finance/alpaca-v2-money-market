// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BaseTest, console } from "../base/BaseTest.sol";

// helper
import { AVDiamondDeployer } from "../helper/AVDiamondDeployer.sol";

abstract contract AV_BaseTest is BaseTest {
  address internal avDiamond;

  function setUp() public virtual {
    avDiamond = AVDiamondDeployer.deployPoolDiamond();
  }
}
