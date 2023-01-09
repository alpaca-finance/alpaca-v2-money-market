// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { LibLYF01 } from "../libraries/LibLYF01.sol";
import { LibDiamond } from "../libraries/LibDiamond.sol";

contract LYFInit {
  error LYFInit_Initialized();

  function init() external {
    LibDiamond.DiamondStorage storage diamondDs = LibDiamond.diamondStorage();
    if (diamondDs.lyfInitialized != 0) revert LYFInit_Initialized();

    diamondDs.lyfInitialized = 1;
  }
}
