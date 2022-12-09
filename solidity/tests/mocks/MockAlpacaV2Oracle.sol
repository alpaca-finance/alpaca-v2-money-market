// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

contract MockAlpacaV2Oracle {
  mapping(address => uint256) mockTokenPrices;

  function setTokenPrice(address _token, uint256 _price) external {
    mockTokenPrices[_token] = _price;
  }

  /// @dev Return value in USD for the given lpAmount.
  function lpToDollar(uint256 _lpAmount, address _lpToken) external view returns (uint256, uint256) {
    return ((mockTokenPrices[_lpToken] * _lpAmount) / 1e18, block.timestamp);
  }

  /// @dev Return amount of LP for the given USD.
  function dollarToLp(uint256 _dollarAmount, address _lpToken) external view returns (uint256, uint256) {
    return (mockTokenPrices[_lpToken], block.timestamp);
  }

  /// @dev Return value of given token in USD.
  function getTokenPrice(address _token) external view returns (uint256, uint256) {
    return (mockTokenPrices[_token], block.timestamp);
  }
}
