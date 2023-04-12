// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../BaseScript.sol";

import { MockAlpacaV2Oracle } from "solidity/tests/mocks/MockAlpacaV2Oracle.sol";

contract CreateLiquidationScenarioScript is BaseScript {
  using stdJson for string;

  function run() public {
    _loadAddresses();

    _startDeployerBroadcast();

    MockAlpacaV2Oracle oracle = new MockAlpacaV2Oracle();
    oracle.setTokenPrice(wbnb, 700 ether);
    oracle.setTokenPrice(ibBnb, 500 ether);
    oracle.setTokenPrice(busd, 1 ether);
    oracle.setTokenPrice(ibBusd, 1 ether);
    oracle.setTokenPrice(usdt, 1 ether);
    oracle.setTokenPrice(doge, 0.8 ether);
    oracle.setTokenPrice(ibDoge, 0.8 ether);
    oracle.setTokenPrice(dodo, 0.3 ether);
    oracle.setTokenPrice(ibDodo, 0.3 ether);

    moneyMarket.setOracle(address(oracle));

    _stopBroadcast();
  }
}
