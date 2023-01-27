// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.17;

// import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";
// import { MMDiamondDeployer } from "../helper/MMDiamondDeployer.sol";

// import { DiamondCutFacet, IDiamondCut } from "../../contracts/money-market/facets/DiamondCutFacet.sol";
// import { DiamondInit } from "../../contracts/money-market/initializers/DiamondInit.sol";
// import { MoneyMarketInit } from "../../contracts/money-market/initializers/MoneyMarketInit.sol";

// contract MoneyMarket_InitializeTest is MoneyMarket_BaseTest {
//   function setUp() public override {
//     super.setUp();
//   }

//   function testRevert_WhenInitDiamondTwice() external {
//     // Deploy DiamondInit
//     DiamondInit diamondInitializer = new DiamondInit();
//     IDiamondCut.FacetCut[] memory facetCuts = new IDiamondCut.FacetCut[](0);

//     vm.expectRevert(abi.encodeWithSelector(DiamondInit.DiamondInit_Initialized.selector));
//     // make lib diamond call init
//     DiamondCutFacet(moneyMarketDiamond).diamondCut(
//       facetCuts,
//       address(diamondInitializer),
//       abi.encodeWithSelector(bytes4(keccak256("init()")))
//     );
//   }

//   function testRevert_WhenInitMoneyMarketTwice() external {
//     MoneyMarketInit _initializer = new MoneyMarketInit();
//     IDiamondCut.FacetCut[] memory facetCuts = new IDiamondCut.FacetCut[](0);

//     vm.expectRevert(abi.encodeWithSelector(MoneyMarketInit.MoneyMarketInit_Initialized.selector));
//     // make lib diamond call init
//     DiamondCutFacet(moneyMarketDiamond).diamondCut(
//       facetCuts,
//       address(_initializer),
//       abi.encodeWithSelector(bytes4(keccak256("init(address,address)")), address(wNativeToken), address(wNativeRelayer))
//     );
//   }
// }
