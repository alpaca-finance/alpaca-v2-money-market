// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "./BaseUtilsScript.sol";

contract SetMoneyMarketConfigsScript is BaseUtilsScript {
  function _run() internal override {
    _startDeployerBroadcast();

    // comment out the one you don't need

    uint256 newMinDebtSize = 0;
    moneyMarket.setMinDebtSize(newMinDebtSize);
    console.log("setMinDebtSize");
    console.log("  newMinDebtSize :", newMinDebtSize, "\n");

    uint8 newMaxNumOfCollat = 0;
    uint8 newMaxNumOfDebt = 0;
    uint8 newMaxNumOfNonCollatDebt = 0;
    moneyMarket.setMaxNumOfToken(newMaxNumOfCollat, newMaxNumOfDebt, newMaxNumOfNonCollatDebt);
    console.log("setMaxNumOfToken");
    console.log("  newMaxNumOfCollat        :", newMaxNumOfCollat);
    console.log("  newMaxNumOfDebt          :", newMaxNumOfDebt);
    console.log("  newMaxNumOfNonCollatDebt :", newMaxNumOfNonCollatDebt, "\n");

    uint16 newLendingFeeBps = 0;
    uint16 newRepurchaseFeeBps = 0;
    uint16 newLiquidationFeeBps = 0;
    uint16 newLiquidationRewardBps = 0;
    moneyMarket.setFees(newLendingFeeBps, newRepurchaseFeeBps, newLiquidationFeeBps, newLiquidationRewardBps);
    console.log("setFees");
    console.log("  newLendingFeeBps        :", newLendingFeeBps);
    console.log("  newRepurchaseFeeBps     :", newRepurchaseFeeBps);
    console.log("  newLiquidationFeeBps    :", newLiquidationFeeBps);
    console.log("  newLiquidationRewardBps :", newLiquidationRewardBps, "\n");

    address newTreasury = address(0);
    moneyMarket.setTreasury(newTreasury);
    console.log("setTreasury");
    console.log("  newTreasury :", newTreasury);

    _stopBroadcast();
  }
}
