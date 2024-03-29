// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

contract WithdrawProtocolReservesScript is BaseScript {
  IAdminFacet.WithdrawProtocolReserveParam[] withdrawProtocolReserveInputs;

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

    address withdrawTo = 0xC44f82b07Ab3E691F826951a6E335E1bC1bB0B51;

    _withdrawAllProtocolReserve(wbnb, withdrawTo);
    _withdrawAllProtocolReserve(usdc, withdrawTo);
    _withdrawAllProtocolReserve(usdt, withdrawTo);
    _withdrawAllProtocolReserve(busd, withdrawTo);
    _withdrawAllProtocolReserve(btcb, withdrawTo);
    _withdrawAllProtocolReserve(eth, withdrawTo);

    //---- execution ----//
    _startDeployerBroadcast();

    moneyMarket.withdrawProtocolReserves(withdrawProtocolReserveInputs);

    _stopBroadcast();

    _logResult();
  }

  function _withdrawAllProtocolReserve(address _token, address _to) internal {
    IAdminFacet.WithdrawProtocolReserveParam memory _input = IAdminFacet.WithdrawProtocolReserveParam({
      token: _token,
      amount: moneyMarket.getProtocolReserve(_token),
      to: _to
    });

    withdrawProtocolReserveInputs.push(_input);
  }

  function _logResult() internal view {
    for (uint256 i; i < withdrawProtocolReserveInputs.length; i++) {
      address _token = withdrawProtocolReserveInputs[i].token;
      uint256 _amount = withdrawProtocolReserveInputs[i].amount;

      console.log("Withdraw token:", IERC20(_token).symbol(), "amount:", _amount);
    }
  }
}
