// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";
import { IAlpacaV2Oracle02 } from "solidity/contracts/oracle/interfaces/IAlpacaV2Oracle02.sol";

contract SetOracleScript is BaseScript {
  using stdJson for string;

  IAlpacaV2Oracle02.SpecificOracle[] _inputs;

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

    address _oracle = alpacaV2Oracle02;
    addTokenAndOracle(address(usdt), _oracle);

    //---- execution ----//
    _startDeployerBroadcast();
    alpacaV2Oracle02.setSpecificOracle(_inputs);
    _stopBroadcast();
  }

  function addTokenAndOracle(address _token, address _oracle) internal {
    IAlpacaV2Oracle02.SpecificOracle memory _input = IAlpacaV2Oracle02.SpecificOracle({
      token: _token,
      oracle: _oracle
    });

    _inputs.push(_input);
  }
}
