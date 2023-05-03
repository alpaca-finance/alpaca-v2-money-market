// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { AlpacaV2Oracle } from "solidity/contracts/oracle/AlpacaV2Oracle.sol";
import { IAlpacaV2Oracle } from "solidity/contracts/oracle/interfaces/IAlpacaV2Oracle.sol";

contract DeployAlpacaV2OracleScript is BaseScript {
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
    address baseStable = usdt;
    address usd = usdPlaceholder;

    _startDeployerBroadcast();

    alpacaV2Oracle = new AlpacaV2Oracle(oracle, baseStable, usd);

    _stopBroadcast();

    _writeJson(vm.toString(address(alpacaV2Oracle)), ".oracle.alpacaV2Oracle");
  }
}
