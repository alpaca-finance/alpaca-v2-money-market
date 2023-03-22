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

    //---- execution ----//
    moneyMarket.withdrawProtocolReserve(tokenToWithdraw, withdrawTo, amountToWithdraw);

    console.log("withdrawProtocolReserve");
    console.log("  tokenToWithdraw  :", tokenToWithdraw);
    console.log("  withdrawTo       :", withdrawTo);
    console.log("  amountToWithdraw :", amountToWithdraw);

    _stopBroadcast();
  }
}
