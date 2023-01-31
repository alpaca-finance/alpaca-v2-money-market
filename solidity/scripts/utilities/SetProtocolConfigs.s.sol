// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "./BaseUtilsScript.sol";
import { LibMoneyMarketDeployment } from "../deployments/libraries/LibMoneyMarketDeployment.sol";

contract SetProtocolConfigsScript is BaseUtilsScript {
  function _run() internal override {
    _startDeployerBroadcast();

    console.log("set non-collat protocol configs");
    IAdminFacet.TokenBorrowLimitInput[] memory tokenBorrowLimitInputs = new IAdminFacet.TokenBorrowLimitInput[](1);
    tokenBorrowLimitInputs[0] = IAdminFacet.TokenBorrowLimitInput({ token: address(0), maxTokenBorrow: 30e18 });

    IAdminFacet.ProtocolConfigInput[] memory protocolConfigInputs = new IAdminFacet.ProtocolConfigInput[](1);
    protocolConfigInputs[0] = IAdminFacet.ProtocolConfigInput({
      account: address(0),
      tokenBorrowLimit: tokenBorrowLimitInputs,
      borrowLimitUSDValue: 1e30
    });

    moneyMarket.setProtocolConfigs(protocolConfigInputs);

    _stopBroadcast();
  }
}
