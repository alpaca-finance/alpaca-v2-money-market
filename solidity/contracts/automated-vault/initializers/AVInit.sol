// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { LibAV01 } from "../libraries/LibAV01.sol";

contract AVInit {
  function init() external {
    LibAV01.AVDiamondStorage storage ds = LibAV01.avDiamondStorage();

    ds.maxPriceStale = 86400;
  }
}
