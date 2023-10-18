// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";
import { IAdminFacet } from "solidity/contracts/money-market/interfaces/IAdminFacet.sol";

contract SetProtocolConfigScript is BaseScript {
  using stdJson for string;

  function run() public {
    /*
  ░██╗░░░░░░░██╗░█████╗░██████╗░███╗░░██╗██╗███╗░░██╗░██████╗░
  ░██║░░██╗░░██║██╔══██╗██╔══██╗████╗░██║██║████╗░██║██╔════╝░
  ░╚██╗████╗██╔╝███████║██████╔╝██╔██╗██║██║██╔██╗██║██║░░██╗░
  ░░████╔═████║░██╔══██║██╔══██╗██║╚████║██║██║╚████║██║░░╚██╗
  ░░╚██╔╝░╚██╔╝░██║░░██║██║░░██║██║░╚███║██║██║░╚███║╚██████╔╝
  ░░░╚═╝░░░╚═╝░░╚═╝░░╚═╝╚═╝░░╚═╝╚═╝░░╚══╝╚═╝╚═╝░░╚══╝░╚═════╝░
  Check all variables below before execute the deployment script
    */

    address _bank = 0xD0dfE9277B1DB02187557eAeD7e25F74eF2DE8f3;
    uint256 _borrowingPowerLimit = 10_000_000 ether;
    IAdminFacet.TokenBorrowLimitInput[] memory _tokenBorrowInputs = new IAdminFacet.TokenBorrowLimitInput[](2);
    _tokenBorrowInputs[0] = IAdminFacet.TokenBorrowLimitInput({ token: eth, maxTokenBorrow: 5000 ether });
    _tokenBorrowInputs[1] = IAdminFacet.TokenBorrowLimitInput({ token: btcb, maxTokenBorrow: 300 ether });

    IAdminFacet.ProtocolConfigInput[] memory _protocolConfigInput = new IAdminFacet.ProtocolConfigInput[](1);
    _protocolConfigInput[0] = IAdminFacet.ProtocolConfigInput({
      account: _bank,
      borrowingPowerLimit: _borrowingPowerLimit,
      tokenBorrowLimit: _tokenBorrowInputs
    });

    //---- execution ----//
    _startDeployerBroadcast();

    moneyMarket.setProtocolConfigs(_protocolConfigInput);

    _stopBroadcast();
  }
}
