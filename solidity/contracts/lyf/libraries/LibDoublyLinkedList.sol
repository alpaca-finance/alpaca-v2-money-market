// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

library LibDoublyLinkedList {
  error LibDoublyLinkedList_Existed();
  error LibDoublyLinkedList_NotExisted();
  error LibDoublyLinkedList_NotInitialized();

  address internal constant START = address(1);
  address internal constant END = address(1);
  address internal constant EMPTY = address(0);

  struct List {
    uint256 size;
    mapping(address => address) next;
    mapping(address => uint256) amount;
    mapping(address => address) prev;
  }

  struct Node {
    address token;
    uint256 amount;
  }

  function init(List storage list) internal {
    list.next[START] = END;
    list.prev[END] = START;
  }

  function has(List storage list, address addr) internal view returns (bool) {
    return list.next[addr] != EMPTY;
  }

  function updateOrRemove(
    List storage list,
    address addr,
    uint256 amount
  ) internal {
    address nextOfAddr = list.next[addr];

    // Check
    if (nextOfAddr == EMPTY) {
      revert LibDoublyLinkedList_NotExisted();
    }

    // Effect
    if (amount == 0) {
      address prevOfAddr = list.prev[addr];

      // cut the node from current link
      list.next[prevOfAddr] = nextOfAddr;
      list.prev[nextOfAddr] = prevOfAddr;

      // cut current link from the node
      list.next[addr] = EMPTY;
      list.prev[addr] = EMPTY;

      --list.size;
    }

    list.amount[addr] = amount;
  }

  /// @dev adding will put `addr` after `START`
  /// ex. START <> BTC <> END => START <> addr <> BTC <> END
  function addOrUpdate(
    List storage list,
    address addr,
    uint256 amount
  ) internal {
    // Check
    // prevent create empty node
    if (amount == 0) {
      return;
    }

    // Effect
    if (!has(list, addr)) {
      // add `addr` to the link after `START`
      address nextOfStart = list.next[START];
      list.next[addr] = nextOfStart;
      list.prev[nextOfStart] = addr;

      list.prev[addr] = START;
      list.next[START] = addr;

      unchecked {
        ++list.size;
      }
    }

    list.amount[addr] = amount;
  }

  function getAmount(List storage list, address addr) internal view returns (uint256) {
    return list.amount[addr];
  }

  function getAll(List storage list) internal view returns (Node[] memory) {
    Node[] memory nodes = new Node[](list.size);
    if (list.size == 0) {
      return nodes;
    }
    address curr = list.next[START];
    for (uint256 i; curr != END; ) {
      nodes[i] = Node({ token: curr, amount: list.amount[curr] });
      curr = list.next[curr];
      unchecked {
        ++i;
      }
    }
    return nodes;
  }

  function getPreviousOf(List storage list, address addr) internal view returns (address) {
    return list.prev[addr];
  }

  function getNextOf(List storage list, address addr) internal view returns (address) {
    return list.next[addr];
  }

  function length(List storage list) internal view returns (uint256) {
    return list.size;
  }
}
