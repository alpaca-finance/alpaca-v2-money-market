// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LibLYF01 } from "../libraries/LibLYF01.sol";

contract LYFInit {
  function init() external {
    LibLYF01.LYFDiamondStorage storage ds = LibLYF01.lyfDiamondStorage();
  }
}
