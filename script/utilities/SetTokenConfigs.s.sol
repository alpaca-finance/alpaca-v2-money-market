// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "./BaseUtilsScript.sol";

import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";
import { IERC20 } from "solidity/contracts/money-market/interfaces/IERC20.sol";

contract SetTokenConfigsScript is BaseUtilsScript {
  address internal mockTokenForLocalRun;

  function _run() internal override {
    _startDeployerBroadcast();

    //---- inputs ----//
    address[] memory tokens = new address[](1);
    tokens[0] = mockTokenForLocalRun;

    IAdminFacet.TokenConfigInput[] memory tokenConfigInputs = new IAdminFacet.TokenConfigInput[](1);
    tokenConfigInputs[0] = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30e18, // be careful on decimals
      maxCollateral: 100e18 // be careful on decimals
    });

    //---- execution ----//
    moneyMarket.setTokenConfigs(tokens, tokenConfigInputs);

    console.log("set config for", tokenConfigInputs.length, "tokens");
    for (uint256 i; i < tokenConfigInputs.length; i++) {
      console.log(" ", IERC20(tokens[i]).symbol());
    }

    _stopBroadcast();
  }
}
