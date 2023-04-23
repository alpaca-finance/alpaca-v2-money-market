// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { IChainLinkPriceOracle } from "solidity/contracts/oracle/interfaces/IChainLinkPriceOracle.sol";
import { IAggregatorV3 } from "solidity/contracts/oracle/interfaces/IAggregatorV3.sol";

contract SetPriceFeedsScript is BaseScript {
  using stdJson for string;

  /// @dev normally there is only 1 aggregator
  struct SetPriceFeedsInput {
    address token0;
    address token1;
    IAggregatorV3 source;
  }

  address[] token0s;
  address[] token1s;
  IAggregatorV3[] allSources;

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

    // CAKE
    addSetPriceFeeds(
      SetPriceFeedsInput({
        token0: cake,
        token1: usdPlaceholder,
        source: IAggregatorV3(0xB6064eD41d4f67e353768aA239cA86f4F73665a1)
      })
    );

    // DOT
    addSetPriceFeeds(
      SetPriceFeedsInput({
        token0: dot,
        token1: usdPlaceholder,
        source: IAggregatorV3(0xC333eb0086309a16aa7c8308DfD32c8BBA0a2592)
      })
    );

    //---- execution ----//
    _startDeployerBroadcast();

    IChainLinkPriceOracle(chainlinkOracle).setPriceFeeds(token0s, token1s, allSources);

    _stopBroadcast();
  }

  function addSetPriceFeeds(SetPriceFeedsInput memory _input) internal {
    token0s.push(_input.token0);
    token1s.push(_input.token1);
    allSources.push(_input.source);
  }
}
