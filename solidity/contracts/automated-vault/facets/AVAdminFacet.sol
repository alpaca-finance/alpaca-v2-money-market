// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// interfaces
import { IAVAdminFacet } from "../interfaces/IAVAdminFacet.sol";

// libraries
import { LibAV01 } from "../libraries/LibAV01.sol";

contract AVAdminFacet is IAVAdminFacet {
  // todo: remove
  function setId(uint8 _id) external {
    LibAV01.getStorage().id = _id;
  }

  // todo: remove
  function getId() external view returns (uint8 _id) {
    _id = LibAV01.getStorage().id;
  }
}
