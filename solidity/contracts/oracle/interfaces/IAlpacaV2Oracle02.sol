// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface IAlpacaV2Oracle02 {
  struct SpecificOracle {
    address token;
    address oracle;
  }

  /// @dev Return value of given token in USD.
  function getTokenPrice(address _token) external view returns (uint256, uint256);

  function oracle() external view returns (address);

  function specificOracles(address _token) external view returns (address);

  function setDefaultOracle(address _oracle) external;

  function setSpecificOracle(SpecificOracle[] memory _input) external;
}
