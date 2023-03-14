// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "../BaseScript.sol";

import { AlpacaV2Oracle } from "solidity/contracts/oracle/AlpacaV2Oracle.sol";

contract DeployOracleScript is BaseScript {
  using stdJson for string;

  function run() public {
    _loadAddresses();

    _startDeployerBroadcast();

    alpacaV2Oracle = address(new AlpacaV2Oracle(oracleMedianizer, usdt, usdPlaceholder));

    moneyMarket.setOracle(alpacaV2Oracle);

    _stopBroadcast();

    _writeJson(vm.toString(alpacaV2Oracle), ".alpacaV2Oracle");
  }
}
