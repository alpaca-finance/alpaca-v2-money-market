// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// ---- External Libraries ---- //
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// ---- Libraries ---- //
import { LibFullMath } from "./libraries/LibFullMath.sol";

// ---- Interfaces ---- //
import { ILiquidityPair } from "./interfaces/ILiquidityPair.sol";
import { IAlpacaV2Oracle02 } from "./interfaces/IAlpacaV2Oracle02.sol";
import { IPriceOracle } from "./interfaces/IPriceOracle.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { IPancakeV3Pool } from "./interfaces/IPancakeV3Pool.sol";

contract AlpacaV2Oracle02 is IAlpacaV2Oracle02, Ownable {
  // Events
  event LogSetDefaultOracle(address indexed _caller, address _newOracle);
  event LogSetSpecificOracle(address _token, address _oracle);

  address internal constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

  // An address of chainlink usd token
  address internal immutable usd;

  // a OracleMedianizer interface to perform get price
  address public oracle;

  // Token => Oracle
  mapping(address => address) public specificOracles;

  constructor(address _oracle, address _usd) {
    oracle = _oracle;
    usd = _usd;
  }

  /// @notice Get token price in dollar
  /// @dev getTokenPrice from address
  /// @param _tokenAddress tokenAddress
  /// @return _price token price in 1e18 format
  /// @return _lastTimestamp the timestamp that price was fed
  function getTokenPrice(address _tokenAddress) external view returns (uint256 _price, uint256 _lastTimestamp) {
    address _oracle = specificOracles[_tokenAddress];
    if (_oracle == address(0)) {
      _oracle = oracle;
    }
    (_price, _lastTimestamp) = IPriceOracle(_oracle).getPrice(_tokenAddress, usd);
  }

  /// @notice Set default oracle
  /// @dev Set default oracle address. Must be called by owner.
  /// @param _oracle oracle address
  function setDefaultOracle(address _oracle) external onlyOwner {
    // sanity call
    IPriceOracle(_oracle).getPrice(WBNB, usd);

    oracle = _oracle;

    emit LogSetDefaultOracle(msg.sender, _oracle);
  }

  /// @notice Set token price on specific oracle
  /// @param _inputs An array of SpecificOracle (token address, oracle address)
  function setSpecificOracle(SpecificOracle[] memory _inputs) external onlyOwner {
    uint256 _len = _inputs.length;
    for (uint256 _i; _i < _len; ) {
      _setSpecificOracle(_inputs[_i].token, _inputs[_i].oracle);

      unchecked {
        ++_i;
      }
    }
  }

  function _setSpecificOracle(address _token, address _oracle) internal {
    // sanity call
    IPriceOracle(_oracle).getPrice(_token, usd);

    specificOracles[_token] = _oracle;
    emit LogSetSpecificOracle(_token, _oracle);
  }
}
