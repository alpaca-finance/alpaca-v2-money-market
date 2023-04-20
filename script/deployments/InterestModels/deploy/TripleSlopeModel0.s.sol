pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { TripleSlopeModel0 } from "solidity/contracts/money-market/interest-models/TripleSlopeModel0.sol";

contract DeployTripleSlopeModel0Script is BaseScript {
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

    _startDeployerBroadcast();
    // deploy implementation
    address interestModel = address(new TripleSlopeModel0());
    _stopBroadcast();

    console.log("Interest Model", interestModel);
  }
}
