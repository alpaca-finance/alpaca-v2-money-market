// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script, console } from "solidity/tests/utils/Script.sol";

import { IChainLinkPriceOracle, IAggregatorV3 } from "../../../solidity/contracts/oracle/interfaces/IChainLinkPriceOracle.sol";

contract SetSourceChainLinkOracle is Script {
  function run() external {
    // https://docs.chain.link/docs/data-feeds/price-feeds/addresses/?network=bnb-chain
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

    address alpacaDeployer = address(0xC44f82b07Ab3E691F826951a6E335E1bC1bB0B51);
    address deployer = vm.addr(deployerPrivateKey);

    if (alpacaDeployer == deployer) {
      vm.startBroadcast(deployer);
    } else {
      vm.startBroadcast();
    }

    address[] memory t0 = new address[](1);
    t0[0] = address(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d);

    address[] memory t1 = new address[](1);
    t1[0] = address(0x115dffFFfffffffffFFFffffFFffFfFfFFFFfFff);

    IAggregatorV3[] memory aggregators = new IAggregatorV3[](1);
    aggregators[0] = IAggregatorV3(address(0x51597f405303C4377E36123cBc172b13269EA163));

    // change this address
    IChainLinkPriceOracle(0x634902128543b25265da350e2d961C7ff540fC71).setPriceFeeds(t0, t1, aggregators);

    vm.stopBroadcast();
  }
}
