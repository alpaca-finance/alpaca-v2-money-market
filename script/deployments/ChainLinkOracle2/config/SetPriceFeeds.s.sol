// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { IChainLinkPriceOracle2 } from "solidity/contracts/oracle/interfaces/IChainLinkPriceOracle2.sol";
import { IAggregatorV3 } from "solidity/contracts/oracle/interfaces/IAggregatorV3.sol";

contract SetPriceFeedsScript is BaseScript {
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

    address _chainLinkPriceOracle2 = 0xEe13333120968d13811Eb2FF7f434ae138578B3e;
    address[] memory token0s = new address[](2);
    address[] memory token1s = new address[](2);
    IAggregatorV3[][] memory allSources = new IAggregatorV3[][](2);

    IAggregatorV3[] memory sources;

    // CAKE
    sources = new IAggregatorV3[](1);
    sources[0] = IAggregatorV3(0xB6064eD41d4f67e353768aA239cA86f4F73665a1);

    token0s[0] = cake;
    token1s[0] = usdPlaceholder;
    allSources[0] = sources;

    // DOT
    sources = new IAggregatorV3[](1);
    sources[0] = IAggregatorV3(0xC333eb0086309a16aa7c8308DfD32c8BBA0a2592);

    token0s[1] = dot;
    token1s[1] = usdPlaceholder;
    allSources[1] = sources;

    _startDeployerBroadcast();

    IChainLinkPriceOracle2(_chainLinkPriceOracle2).setPriceFeeds(token0s, token1s, allSources);

    _stopBroadcast();
  }
}
