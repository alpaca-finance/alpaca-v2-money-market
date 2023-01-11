// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { LibDiamond } from "../libraries/LibDiamond.sol";
import { LibAV01 } from "../libraries/LibAV01.sol";

contract AVInit {
  error AVInit_Initialized();

  function init() external {
    LibDiamond.DiamondStorage storage diamondDs = LibDiamond.diamondStorage();
    if (diamondDs.avInitialized != 0) revert AVInit_Initialized();

    diamondDs.avInitialized = 1;
  }
}
