// SPDX-License-Identifier: BUSL
pragma solidity >=0.8.19;

import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";

interface INonCollatBorrowFacet {
  // Errors
  error NonCollatBorrowFacet_InvalidToken(address _token);
  error NonCollatBorrowFacet_NotEnoughToken(uint256 _borrowAmount);
  error NonCollatBorrowFacet_BorrowingValueTooHigh(
    uint256 _totalBorrowingPower,
    uint256 _totalUsedBorrowingPower,
    uint256 _borrowingUSDValue
  );
  error NonCollatBorrowFacet_InvalidAssetTier();
  error NonCollatBorrowFacet_ExceedBorrowLimit();
  error NonCollatBorrowFacet_ExceedAccountBorrowLimit();
  error NonCollatBorrowFacet_Unauthorized();

  function nonCollatBorrow(address _token, uint256 _amount) external;

  function nonCollatRepay(
    address _account,
    address _token,
    uint256 _repayAmount
  ) external;
}
