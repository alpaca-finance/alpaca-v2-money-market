// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { LibLYF01 } from "../libraries/LibLYF01.sol";
import { LibDiamond } from "../libraries/LibDiamond.sol";
import { IMoneyMarket } from "../interfaces/IMoneyMarket.sol";

contract LYFInit {
  error LYFInit_Initialized();

  function init(address _moneyMarket) external {
    LibDiamond.DiamondStorage storage diamondDs = LibDiamond.diamondStorage();
    if (diamondDs.lyfInitialized != 0) revert LYFInit_Initialized();

    // sanity check for MM
    IMoneyMarket(_moneyMarket).getIbTokenFromToken(address(0));

    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    lyfDs.moneyMarket = IMoneyMarket(_moneyMarket);

    diamondDs.lyfInitialized = 1;
  }
}
