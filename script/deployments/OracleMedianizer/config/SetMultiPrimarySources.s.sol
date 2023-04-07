// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { OracleMedianizer } from "solidity/contracts/oracle/OracleMedianizer.sol";
import { IPriceOracle } from "solidity/contracts/oracle/interfaces/IPriceOracle.sol";

contract SetMultiPrimarySourcesScript is BaseScript {
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
    uint8 pairLength = 3;
    address[] memory token0s = new address[](pairLength);
    address[] memory token1s = new address[](pairLength);
    uint256[] memory maxPriceDeviationList = new uint256[](pairLength);
    uint256[] memory maxPriceStaleList = new uint256[](pairLength);
    IPriceOracle[][] memory allSources = new IPriceOracle[][](pairLength);
    IPriceOracle[] memory souces;

    // BUSD
    souces = new IPriceOracle[](1);
    souces[0] = IPriceOracle(0x634902128543b25265da350e2d961C7ff540fC71);

    token0s[0] = busd;
    token1s[0] = usdPlaceholder;
    maxPriceDeviationList[0] = 1000000000000000000;
    maxPriceStaleList[0] = 86400;
    allSources[0] = souces;

    // BNB
    souces = new IPriceOracle[](1);
    souces[0] = IPriceOracle(0x634902128543b25265da350e2d961C7ff540fC71);

    token0s[1] = wbnb;
    token1s[1] = usdPlaceholder;
    maxPriceDeviationList[1] = 1000000000000000000;
    maxPriceStaleList[1] = 86400;

    allSources[1] = souces;

    // ALPACA
    souces = new IPriceOracle[](1);
    souces[0] = IPriceOracle(0x634902128543b25265da350e2d961C7ff540fC71);

    token0s[2] = alpaca;
    token1s[2] = usdPlaceholder;
    maxPriceDeviationList[2] = 1000000000000000000;
    maxPriceStaleList[2] = 86400;

    allSources[2] = souces;

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
