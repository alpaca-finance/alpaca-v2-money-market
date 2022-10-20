// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LibCollateraleralDoublyLinkedList } from "../libraries/LibCollateraleralDoublyLinkedList.sol";

interface IBorrowFacet {
  function borrow(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external;
}
