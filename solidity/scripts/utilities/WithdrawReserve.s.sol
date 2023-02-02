// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "./BaseUtilsScript.sol";

contract WithdrawReserveScript is BaseUtilsScript {
  address internal mockTokenForLocalRun;

  function _run() internal override {
    _startDeployerBroadcast();

    //---- inputs ----//
    // address tokenToWithdraw = address(0);
    address tokenToWithdraw = mockTokenForLocalRun;
    address withdrawTo = deployerAddress;
    uint256 amountToWithdraw = 0;

    //---- execution ----//
    moneyMarket.withdrawReserve(tokenToWithdraw, withdrawTo, amountToWithdraw);

    console.log("withdrawReserve");
    console.log("  tokenToWithdraw  :", tokenToWithdraw);
    console.log("  withdrawTo       :", withdrawTo);
    console.log("  amountToWithdraw :", amountToWithdraw);

    _stopBroadcast();
  }

  function _setUpForLocalRun() internal override {
    super._setUpForLocalRun();
    mockTokenForLocalRun = _setUpMockToken();
  }
}
