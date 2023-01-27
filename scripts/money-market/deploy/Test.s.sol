// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { Script, console } from "solidity/tests/utils/Script.sol";

import { MMDiamondDeployer } from "../../../solidity/tests/helper/MMDiamondDeployer.sol";
import { DiamondCutFacet, IDiamondCut } from "../../../solidity/contracts/money-market/facets/DiamondCutFacet.sol";
import { MoneyMarketDiamond } from "../../../solidity/contracts/money-market/MoneyMarketDiamond.sol";
import { LibMoneyMarketDeployer } from "../../../solidity/deployments/libraries/LibMoneyMarketDeployer.sol";

contract Test is Script {
  function run() public {
    vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
    // address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
    // console.log(deployer, deployer.balance);

    // address facet = address(new DiamondCutFacet());
    // address mm = address(new MoneyMarketDiamond(address(this), facet));

    // MMDiamondDeployer.deployPoolDiamond(address(1), address(2));

    LibMoneyMarketDeployer.deployMoneyMarket(address(1), address(2));

    vm.stopBroadcast();
  }
}
