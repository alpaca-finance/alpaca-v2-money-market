// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script } from "solidity/tests/utils/Script.sol";
import { SimplePriceOracle } from "solidity/contracts/oracle/SimplePriceOracle.sol";

contract MyScript is Script {
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    SimplePriceOracle simplePriceOracle = new SimplePriceOracle();

    vm.stopBroadcast();
  }
}
