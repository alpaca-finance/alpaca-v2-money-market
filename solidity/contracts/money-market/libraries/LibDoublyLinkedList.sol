// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

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

  function initIfNotExist(List storage list) internal {
    // 1(START) <> 0(EMPTY)
    // 1(START).next = 1(END)
    // 1(END).prev = 1(START)
    // 1(START) <> 1(END)
    if (list.next[START] == EMPTY) {
      list.next[START] = END;
      list.prev[END] = START;
    }
  }

  function has(List storage list, address addr) internal view returns (bool) {
    return list.next[addr] != EMPTY;
  }

  /// @dev removing will cut `addr` from the link
  /// ex. `addr` is BTC
  ///     START <> ETH <> BTC <> END => START <> ETH <> END
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
    // skip removing if `amount` still remain
    //
    // ex. remove BTC:
    //  START   = 1
    //  BTC     = 2 (assume)
    //  ETH     = 3 (assume)
    //  END     = 1
    //  [Current link]: 1 <> 3 <> 2 <> 1
    //
    //  `addr` = 2, since removing BTC
    //  prevOfAddr = 3
    //  nextOfAddr = 1
    //
    //  Step 1: 3(prevOfAddr).next  = 1   -->   1 <- 3 -> 1
    //  Step 2: 1(nextOfAddr).prev  = 3   -->   3 <- 1 -> 0
    //  [Current link]: 1 <> 3 <> 1
    //
    //  Step 3: 2.prev = 0    -->   0 <- 2 -> 1
    //  Step 4: 2.next = 0    -->   0 <- 2 -> 0
    //  [Current link]: 1 <> 3 <> 1
    if (amount == 0) {
      address prevOfAddr = list.prev[addr];

      // cut the node from current link
      // step 1: set next of (prev of `addr`) to be next of `addr`
      list.next[prevOfAddr] = nextOfAddr;
      // step 2: set prev of (next of `addr`) to be prev of `addr`
      list.prev[nextOfAddr] = prevOfAddr;

      // cut current link from the node
      // step 3: set next of `addr` to be EMPTY
      list.next[addr] = EMPTY;
      // step 4: set prev of `addr` to be EMPTY
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
    // skip adding if `addr` already existed
    //
    // ex. add `addr`:
    //  START   = 1
    //  BTC     = 2 (assume)
    //  END     = 1
    //  [Current link]: 1 <> 2 <> 1
    //
    //  `addr`  = 3 (assume)
    //  Initial of 3  -->  0 <- 3 -> 0
    //
    //  Step 1: 3.next  = 2   -->   0 <- 3 -> 2
    //  Step 2: 2.prev  = 3   -->   3 <- 2 -> 1
    //  [Current link]: 0 <> 3 <> 2 <> 1
    //
    //  Step 3: 3.prev = 1    -->   1 <- 3 -> 2
    //  Step 4: 1.next = 3    -->   0 <- 1 -> 3
    //  [Current link]: 1 <> 3 <> 2 <> 1
    if (!has(list, addr)) {
      // add `addr` to the link after `START`
      address nextOfStart = list.next[START];
      // step 1: set next of `addr` to be next of `START`
      list.next[addr] = nextOfStart;
      // step 2: set prev of next of `START` to be `addr`
      list.prev[nextOfStart] = addr;

      // step 3: set prev of `addr` to be `START`
      list.prev[addr] = START;
      // step 4: set next of `START` to be `addr`
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
