// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

library LibUIntDoublyLinkedList {
  error LibUIntDoublyLinkedList_Existed();
  error LibUIntDoublyLinkedList_NotExisted();
  error LibUIntDoublyLinkedList_NotInitialized();

  uint256 internal constant START = 1;
  uint256 internal constant END = 1;
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

  function init(List storage list) internal returns (List storage) {
    list.next[START] = END;
    list.prev[END] = START;
    return list;
  }

  function has(List storage list, uint256 index) internal view returns (bool) {
    return list.next[index] != EMPTY;
  }

  function add(
    List storage list,
    uint256 index,
    uint256 amount
  ) internal returns (List storage) {
    // Check
    if (has(list, index)) revert LibUIntDoublyLinkedList_Existed();

    // Effect
    list.next[index] = list.next[START];
    list.prev[list.next[START]] = index;
    list.prev[index] = START;

    list.next[START] = index;
    list.amount[index] = amount;
    list.size++;

    return list;
  }

  function remove(List storage list, uint256 index) internal returns (List storage) {
    // Check
    if (!has(list, index)) revert LibUIntDoublyLinkedList_NotExisted();

    // Effect
    uint256 prevAddr = list.prev[index];
    list.next[prevAddr] = list.next[index];
    list.prev[list.next[index]] = prevAddr;

    // cut the node from current link
    list.next[index] = EMPTY;
    list.prev[index] = EMPTY;

    list.amount[index] = 0;
    list.size--;

    return list;
  }

  function updateOrRemove(
    List storage list,
    uint256 index,
    uint256 amount
  ) internal returns (List storage) {
    // Check
    if (!has(list, index)) revert LibUIntDoublyLinkedList_NotExisted();

    // Effect
    if (amount == 0) {
      remove(list, index);
    } else {
      list.amount[index] = amount;
    }

    return list;
  }

  function addOrUpdate(
    List storage list,
    uint256 index,
    uint256 amount
  ) internal returns (List storage) {
    // Check
    if (!has(list, index)) {
      add(list, index, amount);
    } else {
      list.amount[index] = amount;
    }

    return list;
  }

  function getAmount(List storage list, uint256 index) internal view returns (uint256) {
    return list.amount[index];
  }

  function getAll(List storage list) internal view returns (Node[] memory) {
    Node[] memory nodes = new Node[](list.size);
    if (list.size == 0) return nodes;
    uint256 curr = list.next[START];
    for (uint256 i = 0; curr != END; i++) {
      nodes[i] = Node({ index: curr, amount: list.amount[curr] });
      curr = list.next[curr];
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
