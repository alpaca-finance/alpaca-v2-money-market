// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "./BaseUtilsScript.sol";

import { InterestBearingToken } from "solidity/contracts/money-market/InterestBearingToken.sol";
import { DebtToken } from "../../contracts/money-market/DebtToken.sol";
import { LibMoneyMarket01 } from "solidity/contracts/money-market/libraries/LibMoneyMarket01.sol";

contract OpenMarketScript is BaseUtilsScript {
  using stdJson for string;

  address internal mockTokenForLocalRun;

  function _run() internal override {
    _startDeployerBroadcast();

    // NOTE: must set ibTokenImplementation before

    //---- inputs ----//
    address underlyingToken = mockTokenForLocalRun;
    IAdminFacet.TokenConfigInput memory underlyingTokenConfigInput = IAdminFacet.TokenConfigInput({
      token: underlyingToken,
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30 ether,
      maxCollateral: 100 ether
    });
    IAdminFacet.TokenConfigInput memory ibTokenConfigInput = IAdminFacet.TokenConfigInput({
      token: underlyingToken,
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30 ether,
      maxCollateral: 100 ether
    });

    //---- execution ----//
    // note: openMarket will ignore `token` provided in TokenConfigInput and use param instead
    address newIbToken = moneyMarket.openMarket(underlyingToken, underlyingTokenConfigInput, ibTokenConfigInput);
    console.log("openMarket for", underlyingToken);

    _stopBroadcast();

    console.log("write output to", configFilePath);
    string memory configJson;
    configJson = configJson.serialize("newIbToken", newIbToken);
    configJson.write(configFilePath, ".IbTokens");
  }

  function _setUpForLocalRun() internal override {
    super._setUpForLocalRun();
    mockTokenForLocalRun = _setUpMockToken();
    address ibTokenImplementation = address(new InterestBearingToken());
    address debtTokenImplemenation = address(new DebtToken());
    vm.broadcast(deployerPrivateKey);
    moneyMarket.setIbTokenImplementation(ibTokenImplementation);
    moneyMarket.setDebtTokenImplementation(debtTokenImplemenation);
  }
}
