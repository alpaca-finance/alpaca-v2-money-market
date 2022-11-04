pragma solidity 0.8.17;

import { IPriceOracle } from "../../contracts/money-market/interfaces/IPriceOracle.sol";

contract MockPriceOracle is IPriceOracle {
  // USD address is 0x115dffFFfffffffffFFFffffFFffFfFfFFFFfFff
  mapping(address => uint256) private _mockPrices;

  function getPrice(
    address _token0,
    address /*_token1*/
  ) external view returns (uint256 _price, uint256 _lastUpdate) {
    _price = _mockPrices[_token0] == 0 ? 1e18 : _mockPrices[_token0];
    _lastUpdate = 0;
  }

  function setPrice(address _token0, uint256 _price) external {
    _mockPrices[_token0] = _price;
  }
}
