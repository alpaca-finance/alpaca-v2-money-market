// SPDX-License-Identifier: MIT
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

  function init(List storage list) internal returns (List storage) {
    list.next[START] = END;
    list.prev[END] = START;
    return list;
  }

  function has(List storage list, address addr) internal view returns (bool) {
    return list.next[addr] != EMPTY;
  }

  function add(
    List storage list,
    address addr,
    uint256 amount
  ) internal returns (List storage) {
    // Check
    if (has(list, addr)) revert LibDoublyLinkedList_Existed();

    // Effect
    list.next[addr] = list.next[START];
    list.prev[list.next[START]] = addr;
    list.prev[addr] = START;

    list.next[START] = addr;
    list.amount[addr] = amount;
    list.size++;

    return list;
  }

  function remove(List storage list, address addr)
    internal
    returns (List storage)
  {
    // Check
    if (!has(list, addr)) revert LibDoublyLinkedList_NotExisted();

    // Effect
    address prevAddr = list.prev[addr];
    list.next[prevAddr] = list.next[addr];
    list.prev[list.next[addr]] = prevAddr;

    // cut the node from current link
    list.next[addr] = EMPTY;
    list.prev[addr] = EMPTY;

    list.amount[addr] = 0;
    list.size--;

    return list;
  }

  function updateOrRemove(
    List storage list,
    address addr,
    uint256 amount
  ) internal returns (List storage) {
    // Check
    if (!has(list, addr)) revert LibDoublyLinkedList_NotExisted();

    // Effect
    if (amount == 0) {
      remove(list, addr);
    } else {
      list.amount[addr] = amount;
    }

    return list;
  }

  function addOrUpdate(
    List storage list,
    address addr,
    uint256 amount
  ) internal returns (List storage) {
    // Check
    if (!has(list, addr)) {
      add(list, addr, amount);
    } else {
      list.amount[addr] = amount;
    }

    return list;
  }

  function getAmount(List storage list, address addr)
    internal
    view
    returns (uint256)
  {
    return list.amount[addr];
  }

  function getAll(List storage list) internal view returns (Node[] memory) {
    Node[] memory nodes = new Node[](list.size);
    if (list.size == 0) return nodes;
    address curr = list.next[START];
    for (uint256 i = 0; curr != END; i++) {
      nodes[i] = Node({ token: curr, amount: list.amount[curr] });
      curr = list.next[curr];
    }
    return nodes;
  }

  function getPreviousOf(List storage list, address addr)
    internal
    view
    returns (address)
  {
    return list.prev[addr];
  }

  function getNextOf(List storage list, address curr)
    internal
    view
    returns (address)
  {
    return list.next[curr];
  }

  function length(List storage list) internal view returns (uint256) {
    return list.size;
  }
}
