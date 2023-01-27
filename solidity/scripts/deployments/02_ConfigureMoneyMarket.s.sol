// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { Script, console } from "solidity/tests/utils/Script.sol";

import { LibMoneyMarketDeployment } from "./libraries/LibMoneyMarketDeployment.sol";

import { InterestBearingToken } from "solidity/contracts/money-market/InterestBearingToken.sol";

import { IAdminFacet } from "solidity/contracts/money-market/interfaces/IAdminFacet.sol";
import { IViewFacet } from "solidity/contracts/money-market/interfaces/IViewFacet.sol";

interface IMoneyMarket is IAdminFacet, IViewFacet {}

contract ConfigureMoneyMarket is Script {
  address internal _moneyMarket;

  function run() public {
    IMoneyMarket moneyMarket = IMoneyMarket(_moneyMarket);

    vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

    // setup ib token
    address ibTokenImplementation = address(new InterestBearingToken());
    console.log(ibTokenImplementation);
    moneyMarket.setIbTokenImplementation(ibTokenImplementation);
    require(moneyMarket.getIbTokenImplementation() == ibTokenImplementation, "setIbTokenImplementation failed");

    vm.stopBroadcast();
  }

  function testRun() public {
    vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
    (_moneyMarket, ) = LibMoneyMarketDeployment.deployMoneyMarket(address(1), address(2));
    vm.stopBroadcast();

    run();
  }
}
