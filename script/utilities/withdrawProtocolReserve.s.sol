// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "./BaseUtilsScript.sol";

contract withdrawProtocolReserveScript is BaseUtilsScript {
  address internal mockTokenForLocalRun;

  function _run() internal override {
    _startDeployerBroadcast();

    //---- inputs ----//
    address tokenToWithdraw = mockTokenForLocalRun;
    address withdrawTo = deployerAddress;
    uint256 amountToWithdraw = 0;
    IAdminFacet.WithdrawProtocolReserveParam[] memory _inputs = new IAdminFacet.WithdrawProtocolReserveParam[](1);
    _inputs[0] = IAdminFacet.WithdrawProtocolReserveParam(tokenToWithdraw, withdrawTo, amountToWithdraw);

    //---- execution ----//
    moneyMarket.withdrawProtocolReserves(_inputs);

    console.log("withdrawProtocolReserve");
    console.log("  tokenToWithdraw  :", tokenToWithdraw);
    console.log("  withdrawTo       :", withdrawTo);
    console.log("  amountToWithdraw :", amountToWithdraw);

    _stopBroadcast();
  }
}
