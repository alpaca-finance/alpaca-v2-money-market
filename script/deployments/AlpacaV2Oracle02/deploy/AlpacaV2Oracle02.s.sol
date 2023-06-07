// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { AlpacaV2Oracle02, IAlpacaV2Oracle02 } from "solidity/contracts/oracle/AlpacaV2Oracle02.sol";

contract DeployAlpacaV2Oracle02Script is BaseScript {
  using stdJson for string;

  function run() public {
    /*
  ░██╗░░░░░░░██╗░█████╗░██████╗░███╗░░██╗██╗███╗░░██╗░██████╗░
  ░██║░░██╗░░██║██╔══██╗██╔══██╗████╗░██║██║████╗░██║██╔════╝░
  ░╚██╗████╗██╔╝███████║██████╔╝██╔██╗██║██║██╔██╗██║██║░░██╗░
  ░░████╔═████║░██╔══██║██╔══██╗██║╚████║██║██║╚████║██║░░╚██╗
  ░░╚██╔╝░╚██╔╝░██║░░██║██║░░██║██║░╚███║██║██║░╚███║╚██████╔╝
  ░░░╚═╝░░░╚═╝░░╚═╝░░╚═╝╚═╝░░╚═╝╚═╝░░╚══╝╚═╝╚═╝░░╚══╝░╚═════╝░
  Check all variables below before execute the deployment script
    */
    address oracle = oracleMedianizer;
    address usd = usdPlaceholder;

    _startDeployerBroadcast();

    alpacaV2Oracle02 = new AlpacaV2Oracle02(oracle, usd);

    _stopBroadcast();

    _writeJson(vm.toString(address(alpacaV2Oracle02)), ".oracle.alpacaV2Oracle");
  }
}
