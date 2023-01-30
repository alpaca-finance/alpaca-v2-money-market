// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { LibUIntDoublyLinkedList } from "../libraries/LibUIntDoublyLinkedList.sol";
import { LibLYF01 } from "../libraries/LibLYF01.sol";

interface ILYFFarmFacet {
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
  error LYFFarmFacet_Unauthorized();
  error LYFFarmFacet_InvalidLP();
  error LYFFarmFacet_BorrowingPowerTooLow();
  error LYFFarmFacet_TooLittleReceived();
  error LYFFarmFacet_CollatNotEnough();

  struct AddFarmPositionInput {
    uint256 subAccountId;
    address lpToken;
    uint256 minLpReceive;
    uint256 desiredToken0Amount;
    uint256 desiredToken1Amount;
    uint256 token0ToBorrow;
    uint256 token1ToBorrow;
    uint256 token0AmountIn;
    uint256 token1AmountIn;
  }

  function addFarmPosition(AddFarmPositionInput calldata _input) external;

  function repay(
    address _account,
    uint256 _subAccountId,
    address _token,
    address _lpToken,
    uint256 _repayAmount
  ) external;

  function reinvest(address _lpToken) external;

  function repayWithCollat(
    uint256 _subAccountId,
    address _token,
    address _lpToken,
    uint256 _repayAmount
  ) external;

  function accrueInterest(address _token, address _lpToken) external;

  function reducePosition(
    uint256 _subAccountId,
    address _lpToken,
    uint256 _lpShareAmount,
    uint256 _amount0Out,
    uint256 _amount1Out
  ) external;
}
