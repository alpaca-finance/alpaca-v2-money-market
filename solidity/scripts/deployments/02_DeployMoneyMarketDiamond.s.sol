// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "./BaseDeploymentScript.sol";

import { LibMoneyMarketDeployment } from "./libraries/LibMoneyMarketDeployment.sol";
import { MoneyMarketDiamond } from "solidity/contracts/money-market/MoneyMarketDiamond.sol";

contract DeployMoneyMarketDiamondScript is BaseDeploymentScript {
  using stdJson for string;

  LibMoneyMarketDeployment.FacetAddresses internal _facetAddresses;

  function _run() internal override {
    _startDeployerBroadcast();

    // deploy money market diamond
    address _moneyMarketDiamond = address(
      new MoneyMarketDiamond(_facetAddresses.diamondCutFacet, deploymentConfig.miniFLAddress)
    );

    _stopBroadcast();

    // write deployed addresses to json
    // NOTE: can't specify order of keys

    // money market
    string memory moneyMarketJson = "MoneyMarket";
    moneyMarketJson = moneyMarketJson.serialize("MoneyMarketDiamond", address(_moneyMarketDiamond));

    // this will overwrite .MoneyMarket.MoneyMarketDiamond key in config file
    moneyMarketJson.write(configFilePath, ".MoneyMarket.MoneyMarketDiamond");
  }

  function _setUpForLocalRun() internal override {
    super._setUpForLocalRun();
    _startDeployerBroadcast();
    _facetAddresses = LibMoneyMarketDeployment.deployMoneyMarketFacets();
    _stopBroadcast();
  }
}
