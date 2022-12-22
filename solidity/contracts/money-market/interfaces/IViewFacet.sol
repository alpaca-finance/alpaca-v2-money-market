// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// libs
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";

interface IViewFacet {
  function getProtocolReserve(address _token) external view returns (uint256 _reserve);

  function tokenConfigs(address _token) external view returns (LibMoneyMarket01.TokenConfig memory);
}
