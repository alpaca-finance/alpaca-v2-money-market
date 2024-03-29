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

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IPriceOracle } from "./interfaces/IPriceOracle.sol";

contract SimplePriceOracle is OwnableUpgradeable, IPriceOracle {
  // struct
  struct PriceData {
    uint192 price;
    uint64 lastUpdate;
  }

  /// ---------------------------------------------------
  /// Errors
  /// ---------------------------------------------------
  error SimplePriceOracle_BadPriceData(address _token0, address _token1);
  error SimplePriceOracle_UnAuthorized(address _token);
  error SimplePriceOracle_InvalidLengthInput();

  /// ---------------------------------------------------
  /// State
  /// ---------------------------------------------------
  address private feeder;
  mapping(address => mapping(address => PriceData)) public store;

  /// ---------------------------------------------------
  /// Event
  /// ---------------------------------------------------
  event LogSetFeeder(address indexed _caller, address _feeder);
  event LogSetPrice(address indexed _token0, address indexed _token1, uint256 _price);

  constructor() {
    _disableInitializers();
  }

  function initialize(address _feeder) external initializer {
    OwnableUpgradeable.__Ownable_init();
    setFeeder(_feeder);
  }

  function setFeeder(address _feeder) public onlyOwner {
    feeder = _feeder;
    emit LogSetFeeder(msg.sender, _feeder);
  }

  function setPrices(
    address[] calldata _token0s,
    address[] calldata _token1s,
    uint256[] calldata _prices
  ) external {
    if (feeder != msg.sender) {
      revert SimplePriceOracle_UnAuthorized(msg.sender);
    }
    uint256 len = _token0s.length;
    if (_token1s.length != len || _prices.length != len) {
      revert SimplePriceOracle_InvalidLengthInput();
    }
    for (uint256 _i; _i < len; ) {
      address token0 = _token0s[_i];
      address token1 = _token1s[_i];
      uint256 price = _prices[_i];
      store[token0][token1] = PriceData({ price: uint192(price), lastUpdate: uint64(block.timestamp) });
      emit LogSetPrice(token0, token1, price);

      unchecked {
        ++_i;
      }
    }
  }

  function getPrice(address _token0, address _token1)
    external
    view
    override
    returns (uint256 price, uint256 lastUpdate)
  {
    PriceData memory data = store[_token0][_token1];
    price = uint256(data.price);
    lastUpdate = uint256(data.lastUpdate);
    if (price == 0 || lastUpdate == 0) {
      revert SimplePriceOracle_BadPriceData(_token0, _token1);
    }
    return (price, lastUpdate);
  }
}
