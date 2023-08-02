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

    address _bank = 0xf21B938af2f70d0b9b79224632B781814938118e;
    uint256 _borrowingPowerLimit = 10_000_000 ether;
    IAdminFacet.TokenBorrowLimitInput[] memory _tokenBorrowInputs = new IAdminFacet.TokenBorrowLimitInput[](2);
    _tokenBorrowInputs[0] = IAdminFacet.TokenBorrowLimitInput({ token: usdt, maxTokenBorrow: 10_000_000 ether });
    _tokenBorrowInputs[1] = IAdminFacet.TokenBorrowLimitInput({ token: wbnb, maxTokenBorrow: 50_000 ether });

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
