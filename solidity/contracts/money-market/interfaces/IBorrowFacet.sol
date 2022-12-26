// SPDX-License-Identifier: BUSL
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

  function repayWithCollat(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _repayAmount
  ) external;

  function accrueInterest(address _token) external;

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
  error BorrowFacet_BorrowingPowerTooLow();
  error BorrowFacet_TooManyCollateralRemoved();
}
