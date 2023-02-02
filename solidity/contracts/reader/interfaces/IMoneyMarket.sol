// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LibMoneyMarket01 } from "../../money-market/libraries/LibMoneyMarket01.sol";

interface IMoneyMarket {
  function getIbTokenFromToken(address _token) external view returns (address);

  function getTokenConfig(address _token) external view returns (LibMoneyMarket01.TokenConfig memory);

  function getGlobalPendingInterest(address _token) external view returns (uint256);

  function getGlobalDebtValue(address _token) external view returns (uint256);

  function getGlobalDebtValueWithPendingInterest(address _token) external view returns (uint256);

  function getDebtLastAccruedAt(address _token) external view returns (uint256);
}
