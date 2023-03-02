// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { IERC173 } from "./IERC173.sol";

interface IOwnershipFacet is IERC173 {
  error OwnershipFacet_CallerIsNotPendingOwner();

  event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

  function owner() external view returns (address);

  function transferOwnership(address _newOwner) external;

  function acceptOwnership() external;

  function pendingOwner() external view returns (address);
}
