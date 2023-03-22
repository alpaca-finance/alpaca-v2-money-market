// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "./BaseUtilsScript.sol";

import { InterestBearingToken } from "solidity/contracts/money-market/InterestBearingToken.sol";
import { DebtToken } from "solidity/contracts/money-market/DebtToken.sol";
import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";

contract OpenMarketScript is BaseUtilsScript {
  using stdJson for string;

  address internal mockTokenForLocalRun;

  function _run() internal override {
    _startDeployerBroadcast();

    // NOTE: must set ibTokenImplementation before

    //---- inputs ----//
    address underlyingToken = mockTokenForLocalRun;

    IAdminFacet.TokenConfigInput memory underlyingTokenConfigInput = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30 ether,
      maxCollateral: 100 ether
    });
    IAdminFacet.TokenConfigInput memory ibTokenConfigInput = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
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
}
