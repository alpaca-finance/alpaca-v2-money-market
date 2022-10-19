// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IAdminFacet {
  struct IbPair {
    address token;
    address ibToken;
  }

  function setTokenToIbTokens(IbPair[] memory _ibPair) external;

  function tokenToIbTokens(address _token) external view returns (address);

  function ibTokenToTokens(address _ibToken) external view returns (address);
}
