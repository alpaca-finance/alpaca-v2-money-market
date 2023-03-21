// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

library LibReentrancyGuard {
  error LibReentrancyGuard_ReentrantCall();

  // -------------
  //    Constants
  // -------------
  // keccak256("moneymarket.reentrancyguard.diamond.storage")
  bytes32 internal constant REENTRANCY_GUARD_STORAGE_POSITION =
    0xbde06addc2781a1cfde79d9c0dd886b1b91b109df0c6d6db84a609c5b38de1fc;

  uint128 internal constant _NOT_ENTERED = 1;
  uint128 internal constant _ENTERED = 2;

  // -------------
  //    Storage
  // -------------
  struct ReentrancyGuardDiamondStorage {
    uint128 status;
    uint128 liquidateExec;
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
    if (reentrancyGuardDs.status == _ENTERED) {
      revert LibReentrancyGuard_ReentrantCall();
    }

    reentrancyGuardDs.status = _ENTERED;
  }

  function unlock() internal {
    ReentrancyGuardDiamondStorage storage reentrancyGuardDs = reentrancyGuardDiamondStorage();
    reentrancyGuardDs.status = _NOT_ENTERED;
  }

  function lockWithdraw() internal {
    ReentrancyGuardDiamondStorage storage reentrancyGuardDs = reentrancyGuardDiamondStorage();

    if (reentrancyGuardDs.status == _ENTERED && reentrancyGuardDs.liquidateExec != _ENTERED) {
      revert LibReentrancyGuard_ReentrantCall();
    }

    reentrancyGuardDs.status = _ENTERED;
  }
}
