// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { AlpacaV2Oracle } from "solidity/contracts/oracle/AlpacaV2Oracle.sol";
import { IAlpacaV2Oracle } from "solidity/contracts/oracle/interfaces/IAlpacaV2Oracle.sol";

contract DeployAlpacaV2OracleScript is BaseScript {
  using stdJson for string;

  function run() public {
    _startDeployerBroadcast();

    alpacaV2Oracle = new AlpacaV2Oracle(0x634902128543b25265da350e2d961C7ff540fC71, busd, usdPlaceholder);

    _stopBroadcast();

    _writeJson(vm.toString(address(alpacaV2Oracle)), ".oracle.alpacaV2Oracle");
  }
}
