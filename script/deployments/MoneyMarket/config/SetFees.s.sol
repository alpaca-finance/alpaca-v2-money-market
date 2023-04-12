// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

contract SetFeesScript is BaseScript {
  using stdJson for string;

  function run() public {
    _loadAddresses();
    /*
  ░██╗░░░░░░░██╗░█████╗░██████╗░███╗░░██╗██╗███╗░░██╗░██████╗░
  ░██║░░██╗░░██║██╔══██╗██╔══██╗████╗░██║██║████╗░██║██╔════╝░
  ░╚██╗████╗██╔╝███████║██████╔╝██╔██╗██║██║██╔██╗██║██║░░██╗░
  ░░████╔═████║░██╔══██║██╔══██╗██║╚████║██║██║╚████║██║░░╚██╗
  ░░╚██╔╝░╚██╔╝░██║░░██║██║░░██║██║░╚███║██║██║░╚███║╚██████╔╝
  ░░░╚═╝░░░╚═╝░░╚═╝░░╚═╝╚═╝░░╚═╝╚═╝░░╚══╝╚═╝╚═╝░░╚══╝░╚═════╝░
  Check all variables below before execute the deployment script
    */

    uint16 _newLendingFeeBps = 15;
    uint16 _newRepurchaseFeeBps = 15;
    uint16 _newLiquidationFeeBps = 15;

    //---- execution ----//
    _startDeployerBroadcast();

    moneyMarket.setFees(_newLendingFeeBps, _newRepurchaseFeeBps, _newLiquidationFeeBps);

    _stopBroadcast();
  }
}
