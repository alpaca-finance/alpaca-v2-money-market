// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../BaseScript.sol";

import { AlpacaV2Oracle } from "solidity/contracts/oracle/AlpacaV2Oracle.sol";
import { IAlpacaV2Oracle } from "solidity/contracts/oracle/interfaces/IAlpacaV2Oracle.sol";

contract DeployOracleScript is BaseScript {
  using stdJson for string;

  function run() public {
    _loadAddresses();

    _startDeployerBroadcast();

    // deploy oracle
    // NOTE: use v1 medianizer
    alpacaV2Oracle = new AlpacaV2Oracle(oracleMedianizer, busd, usdPlaceholder);

    // set alpaca guard path
    address[] memory tokens = new address[](3);
    IAlpacaV2Oracle.Config[] memory configs = new IAlpacaV2Oracle.Config[](3);
    address[] memory path;
    // wbnb
    tokens[0] = wbnb;
    path = new address[](2);
    path[0] = wbnb;
    path[1] = busd;
    configs[0] = IAlpacaV2Oracle.Config({
      router: pancakeswapV2Router,
      maxPriceDiffBps: 10500,
      path: path,
      isUsingV3Pool: false
    });
    // dodo
    tokens[1] = dodo;
    path = new address[](3);
    path[0] = dodo;
    path[1] = wbnb;
    path[2] = busd;
    configs[1] = IAlpacaV2Oracle.Config({
      router: pancakeswapV2Router,
      maxPriceDiffBps: 10500,
      path: path,
      isUsingV3Pool: false
    });
    // doge
    tokens[2] = doge;
    path = new address[](2);
    path[0] = doge;
    path[1] = busd;
    configs[2] = IAlpacaV2Oracle.Config({
      router: pancakeswapV2Router,
      maxPriceDiffBps: 10500,
      path: path,
      isUsingV3Pool: false
    });

    alpacaV2Oracle.setTokenConfig(tokens, configs);

    // set mm oracle
    moneyMarket.setOracle(address(alpacaV2Oracle));

    _stopBroadcast();

    _writeJson(vm.toString(address(alpacaV2Oracle)), ".alpacaV2Oracle");
  }
}
