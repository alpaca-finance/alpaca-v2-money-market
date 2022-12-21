// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { LibDiamond } from "../libraries/LibDiamond.sol";
import { IOwnershipFacet } from "../interfaces/IOwnershipFacet.sol";

contract OwnershipFacet is IOwnershipFacet {
  address private _pendingOwner;

  function transferOwnership(address _newOwner) external override {
    LibDiamond.enforceIsContractOwner();

    _pendingOwner = _newOwner;

    emit OwnershipTransferStarted(LibDiamond.contractOwner(), _newOwner);
  }

  function acceptOwnership() external {
    if (msg.sender != _pendingOwner) revert OwnershipFacet_CallerIsNotPendingOwner();

    address _previousOwner = LibDiamond.contractOwner();
    LibDiamond.setContractOwner(_pendingOwner);
    delete _pendingOwner;

    emit OwnershipTransferred(_previousOwner, LibDiamond.contractOwner());
  }

  /**
   * @dev Returns the address of the current owner.
   */
  function owner() external view override returns (address owner_) {
    owner_ = LibDiamond.contractOwner();
  }

  /**
   * @dev Returns the address of the pending owner.
   */
  function pendingOwner() external view returns (address) {
    return _pendingOwner;
  }
}
