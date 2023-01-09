// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { IAlpacaV2Oracle } from "./IAlpacaV2Oracle.sol";

import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";

interface IMoneyMarket {
  function getOracle() external view returns (IAlpacaV2Oracle);

  function getTokenFromIbToken(address _ibToken) external view returns (address);

  function getTokenConfig(address _token) external view returns (LibMoneyMarket01.TokenConfig memory);

  function getTotalToken(address _token) external view returns (uint256);

  function getTotalTokenWithPendingInterest(address _token) external view returns (uint256 _totalToken);
}
