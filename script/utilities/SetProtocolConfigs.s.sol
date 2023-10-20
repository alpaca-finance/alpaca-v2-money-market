// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "./BaseUtilsScript.sol";
import { LibMoneyMarketDeployment } from "../deployments/libraries/LibMoneyMarketDeployment.sol";

contract SetProtocolConfigsScript is BaseUtilsScript {
  function _run() internal override {
    _startDeployerBroadcast();

    //---- inputs ----//
    address _bank = 0xD0dfE9277B1DB02187557eAeD7e25F74eF2DE8f3;
    uint256 _borrowingPowerLimit = 10_000_000 ether;
    IAdminFacet.TokenBorrowLimitInput[] memory _tokenBorrowInputs = new IAdminFacet.TokenBorrowLimitInput[](1);
    _tokenBorrowInputs[0] = IAdminFacet.TokenBorrowLimitInput({ token: 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d, maxTokenBorrow: 10_000_000 ether });

    IAdminFacet.ProtocolConfigInput[] memory _protocolConfigInput = new IAdminFacet.ProtocolConfigInput[](1);
    _protocolConfigInput[0] = IAdminFacet.ProtocolConfigInput({
      account: _bank,
      borrowingPowerLimit: _borrowingPowerLimit,
      tokenBorrowLimit: _tokenBorrowInputs
    });

    //---- execution ----//
    moneyMarket.setProtocolConfigs(_protocolConfigInput);

    console.log("set non-collat protocol configs");

    _stopBroadcast();
  }
}
