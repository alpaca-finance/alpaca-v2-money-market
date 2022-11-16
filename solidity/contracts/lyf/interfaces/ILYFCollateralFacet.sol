// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";

interface ILYFCollateralFacet {
  function addCollateral(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external;

  function removeCollateral(
    uint256 _subAccountId,
    address _token,
    uint256 _amount
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

  error LYFCollateralFacet_InvalidAssetTier();
  error LYFCollateralFacet_TooManyCollateralRemoved();
  error LYFCollateralFacet_BorrowingPowerTooLow();
  error LYFCollateralFacet_ExceedCollateralLimit();
}
