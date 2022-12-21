// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LibDiamond } from "../libraries/LibDiamond.sol";
import { IERC173 } from "../interfaces/IERC173.sol";

contract OwnershipFacet is IERC173 {
  error OwnershipFacet_Unauthorized();

  address public pendingOwner;

  function transferOwnership(address _newOwner) external override {
    LibDiamond.enforceIsContractOwner();
    pendingOwner = _newOwner;
  }

  function claimOwnership() external {
    if (msg.sender != pendingOwner) revert OwnershipFacet_Unauthorized();
    LibDiamond.setContractOwner(pendingOwner);
  }

  function owner() external view override returns (address owner_) {
    owner_ = LibDiamond.contractOwner();
  }
}
