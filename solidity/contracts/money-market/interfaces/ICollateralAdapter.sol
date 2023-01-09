// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";

interface ICollateralAdapter {
  function getTokenConfig(address _token) external view returns (LibMoneyMarket01.TokenConfig memory);

  function getPrice(address _token) external view returns (uint256 _price);

  function unwrap(
    address _nativeToken,
    address _nativeRelayer,
    address _to,
    uint256 _amount
  ) external;
}
