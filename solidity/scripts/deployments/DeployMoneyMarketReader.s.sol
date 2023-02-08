// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "./BaseDeploymentScript.sol";

import { MoneyMarketReader } from "solidity/contracts/reader/MoneyMarketReader.sol";

contract DeployMoneyMarketFacets is BaseDeploymentScript {
  using stdJson for string;

  function _run() internal override {
    _startDeployerBroadcast();

    address mmReader = address(new MoneyMarketReader(0x7Cd6B7f3Fb066D11eA35dF24Ab9Cdd58292ec352));

    _stopBroadcast();

    // write deployed addresses to json
    // NOTE: can't specify order of keys

    string memory mmReaderJson;
    mmReaderJson = mmReaderJson.serialize("MoneyMarketReader", mmReader);

    // this will overwrite .MoneyMarket.Facets key in config file
    mmReader.write(configFilePath, ".MoneyMarket.Reader");
  }
}
