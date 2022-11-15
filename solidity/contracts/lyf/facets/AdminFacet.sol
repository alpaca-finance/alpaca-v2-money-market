// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LibLYF01 } from "../libraries/LibLYF01.sol";

import { IAdminFacet } from "../interfaces/IAdminFacet.sol";
import { IPriceOracle } from "../interfaces/IPriceOracle.sol";

contract AdminFacet is IAdminFacet {
  function setOracle(address _oracle) external {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    lyfDs.oracle = IPriceOracle(_oracle);
  }

  function oracle() external view returns (address) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    return address(lyfDs.oracle);
  }
}
