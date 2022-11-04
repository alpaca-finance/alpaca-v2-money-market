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

pragma solidity 0.8.17;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IPriceOracle } from "./interfaces/IPriceOracle.sol";

import { IOracleChecker } from "./interfaces/IOracleChecker.sol";
import { LibFullMath } from "../money-market/libraries/LibFullMath.sol";

contract OracleChecker is OwnableUpgradeable, IOracleChecker {
  using LibFullMath for uint256;

  /// @dev Events
  event LogSetOracle(address indexed _caller, address _newOracle);
  event LogSetExpiredToleranceSecond(address indexed caller, address token, uint256 value);
  event LogSetPriceToleranceBps(address indexed caller, address token, uint16 value);

  /// @dev Errors
  error OracleChecker_InvalidOracleAddress();
  error OracleChecker_PriceStale();
  error OracleChecker_ToleranceTooHigh();

  uint256 internal constant MAX_BPS = 10000;

  /// @notice An address of chainlink usd token
  address public usd;
  /// @notice a chainLink interface to perform get price
  IPriceOracle public oracle;

  mapping(address => OracleCheckerTokenConfigStruct) public oracleTokenConfig;

  function initialize(IPriceOracle _oracle, address _usd) public initializer {
    OwnableUpgradeable.__Ownable_init();
    oracle = _oracle;
    usd = _usd;
  }

  /// @notice Get token price in dollar
  /// @dev getTokenPrice from address
  /// @param _tokenAddress tokenAddress
  function getTokenPrice(address _tokenAddress) public view returns (uint256, uint256) {
    (uint256 _price, uint256 _lastTimestamp) = _getOraclePrice(_tokenAddress);

    return (_price, _lastTimestamp);
  }

  /// @notice Set oracle
  /// @dev Set oracle address. Must be called by owner.
  /// @param _oracle oracle address
  function setOracle(address _oracle) external onlyOwner {
    if (_oracle == address(0)) revert OracleChecker_InvalidOracleAddress();

    oracle = IPriceOracle(_oracle);

    emit LogSetOracle(msg.sender, _oracle);
  }

  function setExpiredToleranceSecond(address token, uint256 value) external onlyOwner {
    oracleTokenConfig[token].maxSecondsExpired = value;
    emit LogSetExpiredToleranceSecond(msg.sender, token, value);
  }

  function setPriceToleranceBps(address token, uint16 value) external onlyOwner {
    if (value > MAX_BPS) {
      revert OracleChecker_ToleranceTooHigh();
    }
    oracleTokenConfig[token].toleranceBps = value;
    emit LogSetPriceToleranceBps(msg.sender, token, value);
  }

  function _getOraclePrice(address token) internal view returns (uint256, uint256) {
    (uint256 _price, uint256 _lastUpdated) = oracle.getPrice(token, usd);
    if (_lastUpdated < block.timestamp - oracleTokenConfig[token].maxSecondsExpired) revert OracleChecker_PriceStale();
    return (_price, _lastUpdated);
  }
}
