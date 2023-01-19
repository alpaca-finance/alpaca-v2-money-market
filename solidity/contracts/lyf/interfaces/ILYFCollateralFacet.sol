// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";

interface ILYFCollateralFacet {
  error LYFCollateralFacet_TooManyCollateralRemoved();
  error LYFCollateralFacet_BorrowingPowerTooLow();
  error LYFCollateralFacet_ExceedCollateralLimit();
  error LYFCollateralFacet_TokenNotAllowedAsCollateral(address _token);
  error LYFCollateralFacet_RemoveLPCollateralNotAllowed();

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
}
