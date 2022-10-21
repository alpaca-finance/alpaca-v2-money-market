// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";

interface ICollateralFacet {
  function addCollateral(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external;

  function getCollaterals(address _account, uint256 _subAccountId)
    external
    view
    returns (LibDoublyLinkedList.Node[] memory);
}
