// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../BaseScript.sol";

import { InterestBearingToken } from "solidity/contracts/money-market/InterestBearingToken.sol";
import { DebtToken } from "solidity/contracts/money-market/DebtToken.sol";
import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";
import { MockAlpacaV2Oracle } from "solidity/tests/mocks/MockAlpacaV2Oracle.sol";

contract SetUpMiniFLForTestScript is BaseScript {
  using stdJson for string;

  uint256 internal alpacaPerSecond;

  constructor() {
    alpacaPerSecond = 5e16;
  }

  function run() public {
    _startDeployerBroadcast();

    // seed alpaca to miniFL to be distribute as reward
    // alpaca tokens should be prepared for deployer beforehand
    // in this case bash script should handle it
    IERC20(alpaca).transfer(address(miniFL), 1000 ether);

    miniFL.setAlpacaPerSecond(alpacaPerSecond, false);

    miniFL.setPool(moneyMarket.getMiniFLPoolIdOfToken(moneyMarket.getIbTokenFromToken(wbnb)), 300, false);
    miniFL.setPool(moneyMarket.getMiniFLPoolIdOfToken(moneyMarket.getDebtTokenFromToken(wbnb)), 200, false);

    miniFL.setPool(moneyMarket.getMiniFLPoolIdOfToken(moneyMarket.getIbTokenFromToken(busd)), 100, false);
    miniFL.setPool(moneyMarket.getMiniFLPoolIdOfToken(moneyMarket.getDebtTokenFromToken(busd)), 100, false);

    miniFL.setPool(moneyMarket.getMiniFLPoolIdOfToken(moneyMarket.getIbTokenFromToken(dodo)), 100, false);
    miniFL.setPool(moneyMarket.getMiniFLPoolIdOfToken(moneyMarket.getDebtTokenFromToken(dodo)), 100, false);

    miniFL.setPool(moneyMarket.getMiniFLPoolIdOfToken(moneyMarket.getIbTokenFromToken(doge)), 100, false);
    miniFL.setPool(moneyMarket.getMiniFLPoolIdOfToken(moneyMarket.getDebtTokenFromToken(doge)), 100, false);
  }
}
