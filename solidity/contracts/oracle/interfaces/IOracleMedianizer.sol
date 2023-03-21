// SPDX-License-Identifier: BUSL
/**
  ∩~~~~∩ 
  ξ ･×･ ξ 
  ξ　~　ξ 
  ξ　　 ξ 
  ξ　　 “~～~～〇 
  ξ　　　　　　 ξ 
  ξ ξ ξ~～~ξ ξ ξ 
　 ξ_ξξ_ξ　ξ_ξξ_ξ
Alpaca Fin Corporation
*/
pragma solidity 0.8.19;

import { IPriceOracle } from "./IPriceOracle.sol";

interface IOracleMedianizer is IPriceOracle {
  function primarySourceCount(address token0, address token1) external view returns (uint256 sourceCount);

  function primarySources(
    address token0,
    address token1,
    uint256 index
  ) external view returns (IPriceOracle primarySourceOracle);
}
