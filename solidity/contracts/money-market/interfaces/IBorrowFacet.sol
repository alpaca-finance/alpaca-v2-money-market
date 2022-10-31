// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";

interface IBorrowFacet {
  function borrow(
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external;

  function repay(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _repayAmount
  ) external;

  function getDebtShares(address _account, uint256 _subAccountId)
    external
    view
    returns (LibDoublyLinkedList.Node[] memory);

  function getTotalBorrowingPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalBorrowingPowerUSDValue);

  function getTotalUsedBorrowedPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalBorrowedUSDValue, bool _hasIsolateAsset);

  function getDebt(
    address _account,
    uint256 _subAccountId,
    address _token
  ) external view returns (uint256, uint256);

  function getGlobalDebt(address _token)
    external
    view
    returns (uint256, uint256);

  // Errors
  error BorrowFacet_InvalidToken(address _token);
  error BorrowFacet_NotEnoughToken(uint256 _borrowAmount);
  error BorrowFacet_BorrowingValueTooHigh(
    uint256 _totalBorrowingPowerUSDValue,
    uint256 _totalBorrowedUSDValue,
    uint256 _borrowingUSDValue
  );
  error BorrowFacet_InvalidAssetTier();
  error BorrowFacet_ExceedBorrowLimit();
}
