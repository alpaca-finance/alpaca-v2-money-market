// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "./BaseDeploymentScript.sol";

import { LibMoneyMarketDeployment } from "./libraries/LibMoneyMarketDeployment.sol";
import { MoneyMarketDiamond } from "solidity/contracts/money-market/MoneyMarketDiamond.sol";

contract DeployMoneyMarketDiamond is BaseDeploymentScript {
  using stdJson for string;

  function _run() internal override {
    _startDeployerBroadcast();

    // diamond cut
    LibMoneyMarketDeployment.diamondCutAllMoneyMarketFacets(
      moneyMarketConfig.MoneyMarketDiamond,
      moneyMarketConfig.Facets
    );

    _stopBroadcast();
  }

  function _setUpForLocalRun() internal override {
    super._setUpForLocalRun();
    _startDeployerBroadcast();
    LibMoneyMarketDeployment.FacetAddresses memory _facetAddresses = LibMoneyMarketDeployment.deployMoneyMarketFacets();
    address _moneyMarketDiamond = address(
      new MoneyMarketDiamond(
        _facetAddresses.diamondCutFacet,
        deploymentConfig.wNativeAddress,
        deploymentConfig.wNativeRelayer
      )
    );
    _stopBroadcast();

    moneyMarketConfig = MoneyMarketConfig(_moneyMarketDiamond, _facetAddresses);
  }
}
