// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface IInterestRateModel {
  function getInterestRate(uint256 debt, uint256 floating) external view returns (uint256);

  function CEIL_SLOPE_1() external view returns (uint256);

  function CEIL_SLOPE_2() external view returns (uint256);

  function CEIL_SLOPE_3() external view returns (uint256);

  function MAX_INTEREST_SLOPE_1() external view returns (uint256);

  function MAX_INTEREST_SLOPE_2() external view returns (uint256);

  function MAX_INTEREST_SLOPE_3() external view returns (uint256);
}
