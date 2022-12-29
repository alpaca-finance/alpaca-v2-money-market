// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { AV_BaseTest } from "./AV_BaseTest.t.sol";
import { AVDiamondDeployer } from "../helper/AVDiamondDeployer.sol";

import { DiamondCutFacet, IDiamondCut } from "../../contracts/automated-vault/facets/DiamondCutFacet.sol";
import { DiamondInit } from "../../contracts/automated-vault/initializers/DiamondInit.sol";
import { AVInit } from "../../contracts/automated-vault/initializers/AVInit.sol";

contract AV_InitializeTest is AV_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testRevert_WhenInitAVTwice() external {
    // Deploy DiamondInit
    AVInit _initializer = new AVInit();
    IDiamondCut.FacetCut[] memory facetCuts = new IDiamondCut.FacetCut[](0);

    vm.expectRevert(abi.encodeWithSelector(AVInit.AVInit_Initialized.selector));
    // make lib diamond call init
    DiamondCutFacet(avDiamond).diamondCut(
      facetCuts,
      address(_initializer),
      abi.encodeWithSelector(bytes4(keccak256("init()")))
    );
  }
}
