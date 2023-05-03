// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "./BaseUtilsScript.sol";

/// @notice contains setter for multiple configs. just comment out the one you don't need
contract SetMoneyMarketConfigsScript is BaseUtilsScript {
  function _run() internal override {
    _startDeployerBroadcast();

    //
    // setMinDebtSize
    //

    //---- inputs ----//
    uint256 newMinDebtSize = 0;

    //---- execution ----//
    moneyMarket.setMinDebtSize(newMinDebtSize);
    console.log("setMinDebtSize");
    console.log("  newMinDebtSize :", newMinDebtSize, "\n");

    //
    // setMaxNumOfToken
    //

    //---- inputs ----//
    uint8 newMaxNumOfCollat = 0;
    uint8 newMaxNumOfDebt = 0;
    uint8 newMaxNumOfNonCollatDebt = 0;

    //---- execution ----//
    moneyMarket.setMaxNumOfToken(newMaxNumOfCollat, newMaxNumOfDebt, newMaxNumOfNonCollatDebt);
    console.log("setMaxNumOfToken");
    console.log("  newMaxNumOfCollat        :", newMaxNumOfCollat);
    console.log("  newMaxNumOfDebt          :", newMaxNumOfDebt);
    console.log("  newMaxNumOfNonCollatDebt :", newMaxNumOfNonCollatDebt, "\n");

    //
    // setFees
    //

    //---- inputs ----//
    uint16 newLendingFeeBps = 0;
    uint16 newRepurchaseFeeBps = 0;
    uint16 newLiquidationFeeBps = 0;

    //---- execution ----//
    moneyMarket.setFees(newLendingFeeBps, newRepurchaseFeeBps, newLiquidationFeeBps);
    console.log("setFees");
    console.log("  newLendingFeeBps        :", newLendingFeeBps);
    console.log("  newRepurchaseFeeBps     :", newRepurchaseFeeBps);
    console.log("  newLiquidationFeeBps    :", newLiquidationFeeBps, "\n");

    //
    // setTreasury
    //

    //---- inputs ----//
    address newTreasury = address(0);

    //---- execution ----//
    moneyMarket.setLiquidationTreasury(newTreasury);
    console.log("setTreasury");
    console.log("  newTreasury :", newTreasury);

    _stopBroadcast();
  }
}
