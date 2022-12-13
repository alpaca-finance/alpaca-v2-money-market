// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

library LibAV01 {
  // keccak256("av.diamond.storage");
  bytes32 internal constant AV_STORAGE_POSITION = 0x7829d0c15b32d5078302aaa27ee1e42f0bdf275e05094cc17e0f59b048312982;

  struct AVDiamondStorage {
    uint8 id;
  }

  function getStorage() internal pure returns (AVDiamondStorage storage ds) {
    assembly {
      ds.slot := AV_STORAGE_POSITION
    }
  }
}
