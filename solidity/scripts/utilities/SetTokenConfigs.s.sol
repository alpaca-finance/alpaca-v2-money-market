// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "./BaseUtilsScript.sol";

import { LibMoneyMarket01 } from "solidity/contracts/money-market/libraries/LibMoneyMarket01.sol";
import { IERC20 } from "solidity/contracts/money-market/interfaces/IERC20.sol";

contract SetTokenConfigsScript is BaseUtilsScript {
  address internal mockTokenForLocalRun;

  function _run() internal override {
    _startDeployerBroadcast();

    //---- inputs ----//
    IAdminFacet.TokenConfigInput[] memory tokenConfigInputs = new IAdminFacet.TokenConfigInput[](1);
    tokenConfigInputs[0] = IAdminFacet.TokenConfigInput({
      token: mockTokenForLocalRun,
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30e18, // be careful on decimals
      maxCollateral: 100e18 // be careful on decimals
    });

    //---- execution ----//
    moneyMarket.setTokenConfigs(tokenConfigInputs);

    console.log("set config for", tokenConfigInputs.length, "tokens");
    for (uint256 i; i < tokenConfigInputs.length; i++) {
      console.log(" ", IERC20(tokenConfigInputs[i].token).symbol());
    }

    _stopBroadcast();
  }

  function _setUpForLocalRun() internal override {
    super._setUpForLocalRun();
    mockTokenForLocalRun = _setUpMockToken();
  }
}