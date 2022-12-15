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

  error AVTradeFacet_InvalidToken(address _token);
  error AVAdminFacet_InvalidShareToken(address _token);

  event LogOpenMarket(address indexed _caller, address indexed _token, address _shareToken);

  function openVault(address _token) external returns (address _newShareToken);

  function setTokensToShareTokens(ShareTokenPairs[] calldata pairs) external;

  function setShareTokenConfigs(ShareTokenConfigInput[] calldata configs) external;

  function setMoneyMarket(address _newMoneyMarket) external;

  function setOracle(address _oracle) external;

  function setAVHandler(address _shareToken, address avHandler) external;
}
