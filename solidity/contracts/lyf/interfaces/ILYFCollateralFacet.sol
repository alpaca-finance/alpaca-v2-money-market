// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";

interface ILYFCollateralFacet {
  error LYFCollateralFacet_TooManyCollateralRemoved();
  error LYFCollateralFacet_BorrowingPowerTooLow();
  error LYFCollateralFacet_ExceedCollateralLimit();
  error LYFCollateralFacet_RemoveLPCollateralNotAllowed();
  error LYFCollateralFacet_OnlyCollateralTierAllowed();
  error LYFCollateralFacet_SelfCollatTransferNotAllowed();

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
