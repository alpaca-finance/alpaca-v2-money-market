// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script, console } from "solidity/tests/utils/Script.sol";
// core
import { MoneyMarketDiamond } from "../../../solidity/contracts/money-market/MoneyMarketDiamond.sol";

// facets
import { DiamondCutFacet, IDiamondCut } from "../../../solidity/contracts/money-market/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "../../../solidity/contracts/money-market/facets/DiamondLoupeFacet.sol";
import { LendFacet, ILendFacet } from "../../../solidity/contracts/money-market/facets/LendFacet.sol";
import { CollateralFacet, ICollateralFacet } from "../../../solidity/contracts/money-market/facets/CollateralFacet.sol";
import { BorrowFacet, IBorrowFacet } from "../../../solidity/contracts/money-market/facets/BorrowFacet.sol";
import { NonCollatBorrowFacet, INonCollatBorrowFacet } from "../../../solidity/contracts/money-market/facets/NonCollatBorrowFacet.sol";
import { AdminFacet, IAdminFacet } from "../../../solidity/contracts/money-market/facets/AdminFacet.sol";
import { RepurchaseFacet, IRepurchaseFacet } from "../../../solidity/contracts/money-market/facets/RepurchaseFacet.sol";

// initializers
import { DiamondInit } from "../../../solidity/contracts/money-market/initializers/DiamondInit.sol";

contract DeployFacet is Script {
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

    address alpacaDeployer = address(0xC44f82b07Ab3E691F826951a6E335E1bC1bB0B51);
    address deployer = vm.addr(deployerPrivateKey);
    if (alpacaDeployer == deployer) {
      vm.startBroadcast(deployer);
    } else {
      vm.startBroadcast();
    }
    _deployFacet(alpacaDeployer);
    vm.stopBroadcast();
  }

  function _deployFacet(address owner) internal {
    DiamondCutFacet diamondCutFacet = new DiamondCutFacet();
    DiamondLoupeFacet loupeFacet = new DiamondLoupeFacet();
    LendFacet lendFacet = new LendFacet();
    CollateralFacet collatFacet = new CollateralFacet();
    BorrowFacet borrowFacet = new BorrowFacet();
    NonCollatBorrowFacet nonCollatFacet = new NonCollatBorrowFacet();
    AdminFacet adminFacet = new AdminFacet();
    RepurchaseFacet repurchaseFacet = new RepurchaseFacet();
    DiamondInit diamondInit = new DiamondInit();
  }
}
