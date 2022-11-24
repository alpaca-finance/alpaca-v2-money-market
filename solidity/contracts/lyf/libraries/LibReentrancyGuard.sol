// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

library LibReentrancyGuard {
  error LibReentrancyGuard_ReentrantCall();

  // -------------
  //    Constants
  // -------------
  // keccak256("lyf.reentrancyguard.diamond.storage")
  bytes32 internal constant REENTRANCY_GUARD_STORAGE_POSITION =
    0xa1429e1b482f5222c74c2ab4eba141c326acd1d62417da92c7231029b5f364d0;

  uint256 internal constant _NOT_ENTERED = 1;
  uint256 internal constant _ENTERED = 2;

  // -------------
  //    Storage
  // -------------
  struct ReentrancyGuardDiamondStorage {
    uint256 status;
  }

  function reentrancyGuardDiamondStorage()
    internal
    pure
    returns (ReentrancyGuardDiamondStorage storage reentrancyGuardDs)
  {
    assembly {
      reentrancyGuardDs.slot := REENTRANCY_GUARD_STORAGE_POSITION
    }
  }

  function lock() internal {
    ReentrancyGuardDiamondStorage storage reentrancyGuardDs = reentrancyGuardDiamondStorage();
    if (reentrancyGuardDs.status == _ENTERED) revert LibReentrancyGuard_ReentrantCall();

    reentrancyGuardDs.status = _ENTERED;
  }

  function unlock() internal {
    ReentrancyGuardDiamondStorage storage reentrancyGuardDs = reentrancyGuardDiamondStorage();
    reentrancyGuardDs.status = _NOT_ENTERED;
  }
}
