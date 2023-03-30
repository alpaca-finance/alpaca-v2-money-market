// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { OracleMedianizer } from "solidity/contracts/oracle/OracleMedianizer.sol";
import { IPriceOracle } from "solidity/contracts/oracle/interfaces/IPriceOracle.sol";

contract SetMultiPrimarySourcesScript is BaseScript {
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
    uint8 pairLength = 1;
    address[] memory token0s = new address[](pairLength);
    address[] memory token1s = new address[](pairLength);
    uint256[] memory maxPriceDeviationList = new uint256[](pairLength);
    uint256[] memory maxPriceStaleList = new uint256[](pairLength);
    IPriceOracle[][] memory allSources = new IPriceOracle[][](pairLength);

    token0s[0] = busd;
    token1s[0] = usdPlaceholder;
    maxPriceDeviationList[0] = 1000000000000000000;
    maxPriceStaleList[0] = 86400;
    IPriceOracle[] memory souces = new IPriceOracle[](1);
    souces[0] = IPriceOracle(0x634902128543b25265da350e2d961C7ff540fC71);
    allSources[0] = souces;

    _startDeployerBroadcast();

    OracleMedianizer(address(oracleMedianizer)).setMultiPrimarySources(
      token0s,
      token1s,
      maxPriceDeviationList,
      maxPriceStaleList,
      allSources
    );

    _stopBroadcast();
  }
}
