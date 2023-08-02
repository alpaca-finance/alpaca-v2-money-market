// SPDX-License-Identifier: BUSL
pragma solidity >=0.8.19;

import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";

interface ICollateralFacet {
  error CollateralFacet_NoSelfTransfer();

  function addCollateral(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external;

  function removeCollateral(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _removeAmount
  ) external;

  function transferCollateral(
    address _account,
    uint256 _fromSubAccountId,
    uint256 _toSubAccountId,
    address _token,
    uint256 _amount
  ) external;
}
