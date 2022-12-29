// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest } from "./LYF_BaseTest.t.sol";
import { LYFDiamondDeployer } from "../helper/LYFDiamondDeployer.sol";

import { DiamondCutFacet, IDiamondCut } from "../../contracts/lyf/facets/DiamondCutFacet.sol";
import { DiamondInit } from "../../contracts/lyf/initializers/DiamondInit.sol";
import { LYFInit } from "../../contracts/lyf/initializers/LYFInit.sol";

contract LYF_Init is LYF_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testRevert_WhenInitLYFTwice() external {
    LYFInit _initializer = new LYFInit();
    IDiamondCut.FacetCut[] memory facetCuts = new IDiamondCut.FacetCut[](0);

    vm.expectRevert(abi.encodeWithSelector(LYFInit.LYFInit_Initialized.selector));
    // make lib diamond call init
    DiamondCutFacet(lyfDiamond).diamondCut(
      facetCuts,
      address(_initializer),
      abi.encodeWithSelector(bytes4(keccak256("init()")))
    );
  }
}
