// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { IERC173 } from "./IERC173.sol";

interface ILYFOwnershipFacet is IERC173 {
  error LYFOwnershipFacet_CallerIsNotPendingOwner();

  event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

  function acceptOwnership() external;

  function pendingOwner() external view returns (address);
}
