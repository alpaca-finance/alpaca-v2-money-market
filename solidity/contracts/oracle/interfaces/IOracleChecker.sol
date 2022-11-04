// SPDX-License-Identifier: MIT
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
pragma solidity 0.8.17;

interface IOracleChecker {
  struct OracleCheckerTokenConfigStruct {
    uint256 toleranceExpiredSecond;
  }

  function getTokenPrice(address _tokenAddress) external view returns (uint256, uint256);

  function setOracle(address _oracle) external;

  function setExpiredToleranceSecond(address token, uint256 value) external;
}
