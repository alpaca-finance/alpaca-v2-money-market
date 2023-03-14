// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "../BaseScript.sol";

import { AlpacaV2Oracle } from "solidity/contracts/oracle/AlpacaV2Oracle.sol";
import { IAlpacaV2Oracle } from "solidity/contracts/oracle/interfaces/IAlpacaV2Oracle.sol";

contract DeployOracleScript is BaseScript {
  using stdJson for string;

  function run() public {
    _loadAddresses();

    _startDeployerBroadcast();

    // deploy oracle
    alpacaV2Oracle = new AlpacaV2Oracle(oracleMedianizer, usdt, usdPlaceholder);

    // set alpaca guard path
    address[] memory tokens = new address[](1);
    tokens[0] = busd;
    address[] memory path = new address[](2);
    path[0] = busd;
    path[1] = usdt;
    IAlpacaV2Oracle.Config[] memory configs = new IAlpacaV2Oracle.Config[](1);
    configs[0] = IAlpacaV2Oracle.Config({ router: pancakeswapV2Router, maxPriceDiffBps: 10500, path: path });
    alpacaV2Oracle.setTokenConfig(tokens, configs);

    // set mm oracle
    moneyMarket.setOracle(address(alpacaV2Oracle));

    _stopBroadcast();

    _writeJson(vm.toString(address(alpacaV2Oracle)), ".alpacaV2Oracle");
  }
}
