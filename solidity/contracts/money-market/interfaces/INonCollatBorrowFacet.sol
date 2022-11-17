// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";

interface INonCollatBorrowFacet {
  function nonCollatBorrow(address _token, uint256 _amount) external;

  function nonCollatRepay(
    address _account,
    address _token,
    uint256 _repayAmount
  ) external;

  function nonCollatGetDebtValues(address _account) external view returns (LibDoublyLinkedList.Node[] memory);

  function nonCollatGetTotalUsedBorrowedPower(address _account)
    external
    view
    returns (uint256 _totalBorrowedUSDValue, bool _hasIsolateAsset);

  function nonCollatGetDebt(address _account, address _token) external view returns (uint256);

  function nonCollatGetTokenDebt(address _token) external view returns (uint256);

  function nonCollatBorrowLimitUSDValues(address _account) external view returns (uint256);

  function getNonCollatInterestRate(address _account, address _token) external view returns (uint256);

  // Errors
  error NonCollatBorrowFacet_InvalidToken(address _token);
  error NonCollatBorrowFacet_NotEnoughToken(uint256 _borrowAmount);
  error NonCollatBorrowFacet_BorrowingValueTooHigh(
    uint256 _totalBorrowingPowerUSDValue,
    uint256 _totalBorrowedUSDValue,
    uint256 _borrowingUSDValue
  );
  error NonCollatBorrowFacet_InvalidAssetTier();
  error NonCollatBorrowFacet_ExceedBorrowLimit();
  error NonCollatBorrowFacet_Unauthorized();
}
