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

  function removeCollateral(
    uint256 _subAccountId,
    address _token,
    uint256 _removeAmount
  ) external;

  function transferCollateral(
    uint256 _fromSubAccountId,
    uint256 _toSubAccountId,
    address _token,
    uint256 _amount
  ) external;

  function getCollaterals(address _account, uint256 _subAccountId)
    external
    view
    returns (LibDoublyLinkedList.Node[] memory);

  function collats(address _token) external view returns (uint256);

  function subAccountCollatAmount(address _subAccount, address _token) external view returns (uint256);

  // erros
  error CollateralFacet_InvalidAssetTier();
  error CollateralFacet_TooManyCollateralRemoved();
  error CollateralFacet_BorrowingPowerTooLow();
  error CollateralFacet_ExceedCollateralLimit();
}
