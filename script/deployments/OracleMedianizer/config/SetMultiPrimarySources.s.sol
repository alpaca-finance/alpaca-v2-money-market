// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { OracleMedianizer } from "solidity/contracts/oracle/OracleMedianizer.sol";
import { IPriceOracle } from "solidity/contracts/oracle/interfaces/IPriceOracle.sol";

contract SetMultiPrimarySourcesScript is BaseScript {
  using stdJson for string;

  struct SetMultiPrimarySourcesInput {
    address token0;
    address token1;
    uint256 maxPriceDeviation;
    uint256 maxPriceStale;
    IPriceOracle[] priceSources;
  }

  address[] token0s;
  address[] token1s;
  uint256[] maxPriceDeviationList;
  uint256[] maxPriceStaleList;
  IPriceOracle[][] allSources;

  IPriceOracle[] chainlinkPriceSource;

  constructor() {
    chainlinkPriceSource.push(IPriceOracle(chainlinkPriceOracle));
  }

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
    addSetMultiPrimarySources(
      SetMultiPrimarySourcesInput({
        token0: cake,
        token1: usdPlaceholder,
        maxPriceDeviation: 1000000000000000000,
        maxPriceStale: 86400,
        priceSources: chainlinkPriceSource
      })
    );

    // DOT
    addSetMultiPrimarySources(
      SetMultiPrimarySourcesInput({
        token0: dot,
        token1: usdPlaceholder,
        maxPriceDeviation: 1000000000000000000,
        maxPriceStale: 86400,
        priceSources: chainlinkPriceSource
      })
    );

    //---- execution ----//
    _startDeployerBroadcast();

    OracleMedianizer(oracleMedianizer).setMultiPrimarySources(
      token0s,
      token1s,
      maxPriceDeviationList,
      maxPriceStaleList,
      allSources
    );

    _stopBroadcast();
  }

  function addSetMultiPrimarySources(SetMultiPrimarySourcesInput memory _input) internal {
    token0s.push(_input.token0);
    token1s.push(_input.token1);
    maxPriceDeviationList.push(_input.maxPriceDeviation);
    maxPriceStaleList.push(_input.maxPriceStale);
    allSources.push(_input.priceSources);
  }
}
