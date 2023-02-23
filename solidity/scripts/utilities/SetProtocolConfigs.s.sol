// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "./BaseUtilsScript.sol";
import { LibMoneyMarketDeployment } from "../deployments/libraries/LibMoneyMarketDeployment.sol";

contract SetProtocolConfigsScript is BaseUtilsScript {
  function _run() internal override {
    _startDeployerBroadcast();

    //---- inputs ----//
    IAdminFacet.TokenBorrowLimitInput[] memory tokenBorrowLimitInputs = new IAdminFacet.TokenBorrowLimitInput[](1);
    tokenBorrowLimitInputs[0] = IAdminFacet.TokenBorrowLimitInput({
      token: address(0),
      maxTokenBorrow: 30e18 // be careful on decimals
    });

    IAdminFacet.ProtocolConfigInput[] memory protocolConfigInputs = new IAdminFacet.ProtocolConfigInput[](1);
    protocolConfigInputs[0] = IAdminFacet.ProtocolConfigInput({
      account: address(0),
      tokenBorrowLimit: tokenBorrowLimitInputs,
      borrowLimitUSDValue: 1e30 // note that this is usd value
    });

    //---- execution ----//
    moneyMarket.setProtocolConfigs(protocolConfigInputs);

    console.log("set non-collat protocol configs");

    _stopBroadcast();
  }
}
