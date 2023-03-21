// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

library LibUIntDoublyLinkedList {
  error LibUIntDoublyLinkedList_Existed();
  error LibUIntDoublyLinkedList_NotExisted();
  error LibUIntDoublyLinkedList_NotInitialized();

  uint256 internal constant START = type(uint256).max;
  uint256 internal constant END = type(uint256).max;
  uint256 internal constant EMPTY = 0;

  struct List {
    uint256 size;
    mapping(uint256 => uint256) next;
    mapping(uint256 => uint256) amount;
    mapping(uint256 => uint256) prev;
  }

  struct Node {
    uint256 index;
    uint256 amount;
  }

  function initIfNotExist(List storage list) internal {
    if (list.next[START] == EMPTY) {
      list.next[START] = END;
      list.prev[END] = START;
    }
  }

  function has(List storage list, uint256 index) internal view returns (bool) {
    return list.next[index] != EMPTY;
  }

  function updateOrRemove(
    List storage list,
    uint256 index,
    uint256 amount
  ) internal {
    uint256 nextOfIndex = list.next[index];

    // Check
    if (nextOfIndex == EMPTY) {
      revert LibUIntDoublyLinkedList_NotExisted();
    }

    // Effect
    if (amount == 0) {
      uint256 prevAddr = list.prev[index];

      // cut the node from current link
      list.next[prevAddr] = nextOfIndex;
      list.prev[nextOfIndex] = prevAddr;

      // cut current link from the node
      list.next[index] = EMPTY;
      list.prev[index] = EMPTY;

      --list.size;
    }

    list.amount[index] = amount;
  }

  function addOrUpdate(
    List storage list,
    uint256 index,
    uint256 amount
  ) internal {
    // Check
    // prevent create empty node
    if (amount == 0) {
      return;
    }

    // Effect
    // add `index` to the link after `START`
    if (!has(list, index)) {
      uint256 nextOfStart = list.next[START];
      list.next[index] = nextOfStart;
      list.prev[nextOfStart] = index;

      list.prev[index] = START;
      list.next[START] = index;

      unchecked {
        ++list.size;
      }
    }

    list.amount[index] = amount;
  }

  function getAmount(List storage list, uint256 index) internal view returns (uint256) {
    return list.amount[index];
  }

  function getAll(List storage list) internal view returns (Node[] memory) {
    Node[] memory nodes = new Node[](list.size);
    if (list.size == 0) {
      return nodes;
    }
    uint256 curr = list.next[START];
    for (uint256 i; curr != END; ) {
      nodes[i] = Node({ index: curr, amount: list.amount[curr] });
      curr = list.next[curr];
      unchecked {
        ++i;
      }
    }
    return nodes;
  }

  function getPreviousOf(List storage list, uint256 index) internal view returns (uint256) {
    return list.prev[index];
  }

  function getNextOf(List storage list, uint256 index) internal view returns (uint256) {
    return list.next[index];
  }

  function length(List storage list) internal view returns (uint256) {
    return list.size;
  }
}
