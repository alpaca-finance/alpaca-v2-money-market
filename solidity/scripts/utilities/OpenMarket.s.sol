// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "./BaseUtilsScript.sol";

import { InterestBearingToken } from "solidity/contracts/money-market/InterestBearingToken.sol";

contract OpenMarketScript is BaseUtilsScript {
  using stdJson for string;

  address internal mockTokenForLocalRun;

  function _run() internal override {
    _startDeployerBroadcast();

    // NOTE: must set ibTokenImplementation before

    //---- inputs ----//
    address underlyingToken = mockTokenForLocalRun;

    //---- execution ----//
    (address newIbToken, address newDebtToken) = moneyMarket.openMarket(underlyingToken);
    console.log("openMarket for", underlyingToken);

    _stopBroadcast();

    console.log("write output to", configFilePath);
    string memory configJson;
    configJson = configJson.serialize("newIbToken", newIbToken);
    configJson.write(configFilePath, ".IbTokens");
    configJson = configJson.serialize("newDebtToken", newDebtToken);
    configJson.write(configFilePath, ".DebtTokens");
  }

  function _setUpForLocalRun() internal override {
    super._setUpForLocalRun();
    mockTokenForLocalRun = _setUpMockToken();
    address ibTokenImplementation = address(new InterestBearingToken());
    vm.broadcast(deployerPrivateKey);
    moneyMarket.setIbTokenImplementation(ibTokenImplementation);
  }
}
