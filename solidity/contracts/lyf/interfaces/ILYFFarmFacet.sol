// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { LibUIntDoublyLinkedList } from "../libraries/LibUIntDoublyLinkedList.sol";

interface ILYFFarmFacet {
  function addFarmPosition(
    uint256 _subAccountId,
    address _lpToken,
    uint256 _desireToken0Amount,
    uint256 _desireToken1Amount,
    uint256 _minLpReceive
  ) external;

  function directAddFarmPosition(
    uint256 _subAccountId,
    address _lpToken,
    uint256 _desireToken0Amount,
    uint256 _desireToken1Amount,
    uint256 _minLpReceive,
    uint256 _token0AmountIn,
    uint256 _token1AmountIn
  ) external;

  function repay(
    address _account,
    uint256 _subAccountId,
    address _token,
    address _lpToken,
    uint256 _repayAmount
  ) external;

  function getDebtShares(address _account, uint256 _subAccountId)
    external
    view
    returns (LibUIntDoublyLinkedList.Node[] memory);

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
    address _token,
    address _lpToken
  ) external view returns (uint256, uint256);

  function getGlobalDebt(address _token, address _lpToken) external view returns (uint256, uint256);

  function debtLastAccureTime(address _token, address _lpToken) external view returns (uint256);

  function pendingInterest(address _token, address _lpToken) external view returns (uint256);

  function accureInterest(address _token, address _lpToken) external;

  function debtValues(address _token, address _lpToken) external view returns (uint256);

  function debtShares(address _token, address _lpToken) external view returns (uint256);

  function reducePosition(
    uint256 _subAccountId,
    address _lpToken,
    uint256 _lpShareAmount,
    uint256 _amount0Out,
    uint256 _amount1Out
  ) external;

  function getMMDebt(address _token) external view returns (uint256);

  // Errors
  error LYFFarmFacet_InvalidToken(address _token);
  error LYFFarmFacet_NotEnoughToken(uint256 _borrowAmount);
  error LYFFarmFacet_BorrowingValueTooHigh(
    uint256 _totalBorrowingPowerUSDValue,
    uint256 _totalBorrowedUSDValue,
    uint256 _borrowingUSDValue
  );
  error LYFFarmFacet_InvalidAssetTier();
  error LYFFarmFacet_ExceedBorrowLimit();
  error LYFFarmFacet_BadInput();
}
