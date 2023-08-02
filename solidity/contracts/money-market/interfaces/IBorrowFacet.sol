// SPDX-License-Identifier: BUSL
pragma solidity >=0.8.19;

import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";

interface IBorrowFacet {
  // Errors
  error BorrowFacet_InvalidToken(address _token);
  error BorrowFacet_NotEnoughToken(uint256 _borrowAmount);
  error BorrowFacet_BorrowingValueTooHigh(
    uint256 _totalBorrowingPower,
    uint256 _totalUsedBorrowingPower,
    uint256 _borrowingUSDValue
  );
  error BorrowFacet_InvalidAssetTier();
  error BorrowFacet_ExceedBorrowLimit();
  error BorrowFacet_BorrowLessThanMinDebtSize();
  error BorrowFacet_TooManyCollateralRemoved();
  error BorrowFacet_NoDebtToRepay();

  function borrow(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external;

  function repay(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _debtShareAmount
  ) external;

  function repayWithCollat(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _debtShareAmount
  ) external;

  function accrueInterest(address _token) external;
}
