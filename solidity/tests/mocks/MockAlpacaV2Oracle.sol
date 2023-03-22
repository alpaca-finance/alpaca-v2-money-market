// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract MockAlpacaV2Oracle {
  mapping(address => uint256) mockTokenPrices;
  mapping(address => uint256) mockLpTokenPrices;

  function setTokenPrice(address _token, uint256 _price) external {
    mockTokenPrices[_token] = _price;
  }

  function setLpTokenPrice(address _lpToken, uint256 _price) external {
    mockLpTokenPrices[_lpToken] = _price;
  }

  /// @dev Return value in USD for the given lpAmount.
  function lpToDollar(uint256 _lpAmount, address _lpToken) external view returns (uint256, uint256) {
    if (_lpAmount == 0) {
      return (0, block.timestamp);
    }
    return ((mockLpTokenPrices[_lpToken] * _lpAmount) / 1e18, block.timestamp);
  }

  /// @dev Return amount of LP for the given USD.
  function dollarToLp(uint256 _dollarAmount, address _lpToken) external view returns (uint256, uint256) {
    if (_dollarAmount == 0) {
      return (0, block.timestamp);
    }
    return ((_dollarAmount * 1e18) / mockLpTokenPrices[_lpToken], block.timestamp);
  }

  /// @dev Return value of given token in USD.
  function getTokenPrice(address _token) external view returns (uint256, uint256) {
    return (mockTokenPrices[_token], block.timestamp);
  }
}
