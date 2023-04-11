// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { InterestBearingToken } from "solidity/contracts/money-market/InterestBearingToken.sol";
import { DebtToken } from "solidity/contracts/money-market/DebtToken.sol";
import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";

contract OpenMarketScript is BaseScript {
  using stdJson for string;

  function run() public {
    _loadAddresses();
    /*
  ░██╗░░░░░░░██╗░█████╗░██████╗░███╗░░██╗██╗███╗░░██╗░██████╗░
  ░██║░░██╗░░██║██╔══██╗██╔══██╗████╗░██║██║████╗░██║██╔════╝░
  ░╚██╗████╗██╔╝███████║██████╔╝██╔██╗██║██║██╔██╗██║██║░░██╗░
  ░░████╔═████║░██╔══██║██╔══██╗██║╚████║██║██║╚████║██║░░╚██╗
  ░░╚██╔╝░╚██╔╝░██║░░██║██║░░██║██║░╚███║██║██║░╚███║╚██████╔╝
  ░░░╚═╝░░░╚═╝░░╚═╝░░╚═╝╚═╝░░╚═╝╚═╝░░╚══╝╚═╝╚═╝░░╚══╝░╚═════╝░
  Check all variables below before execute the deployment script
    */

    //---- inputs ----//
    address underlyingToken = wbnb;

    IAdminFacet.TokenConfigInput memory underlyingTokenConfigInput = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 0,
      borrowingFactor: 9000,
      maxBorrow: 10_000 ether,
      maxCollateral: 0 ether
    });
    IAdminFacet.TokenConfigInput memory ibTokenConfigInput = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 0 ether,
      maxCollateral: 1_000_000 ether
    });

    //---- execution ----//
    _startDeployerBroadcast();
    address newIbToken = moneyMarket.openMarket(underlyingToken, underlyingTokenConfigInput, ibTokenConfigInput);
    _stopBroadcast();

    console.log("openMarket for", underlyingToken);

    // TODO: add new ib and debt token in miniFL pools
    // string memory configJson;
    // configJson = configJson.serialize("newIbToken", newIbToken);
    // configJson.write(configFilePath, ".IbTokens");
  }
}
