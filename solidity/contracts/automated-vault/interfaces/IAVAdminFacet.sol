// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IAVAdminFacet {
  struct ShareTokenPairs {
    address token;
    address shareToken;
  }

  struct ShareTokenConfigInput {
    address shareToken;
    uint256 someConfig; // TODO: replace with real config
  }

  function setTokensToShareTokens(ShareTokenPairs[] calldata pairs) external;
}
