// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import { IERC173 } from "./IERC173.sol";

interface IMMOwnershipFacet is IERC173 {
  error MMOwnershipFacet_CallerIsNotPendingOwner();

  event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

  function owner() external view returns (address);

  function transferOwnership(address _newOwner) external;

  function acceptOwnership() external;

  function pendingOwner() external view returns (address);
}
