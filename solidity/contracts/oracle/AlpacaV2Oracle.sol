// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// ---- External Libraries ---- //
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// ---- Libraries ---- //
import { LibFullMath } from "./libraries/LibFullMath.sol";

// ---- Interfaces ---- //
import { ILiquidityPair } from "./interfaces/ILiquidityPair.sol";
import { IAlpacaV2Oracle } from "./interfaces/IAlpacaV2Oracle.sol";
import { IPriceOracle } from "./interfaces/IPriceOracle.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { IRouterLike } from "./interfaces/IRouterLike.sol";

contract AlpacaV2Oracle is IAlpacaV2Oracle, Initializable, OwnableUpgradeable {
  using LibFullMath for uint256;

  /// @dev Events
  event LogSetOracle(address indexed _caller, address _newOracle);

  /// @notice An address of chainlink usd token
  address public usd;

  address public baseStable;

  /// @notice a chainLink interface to perform get price
  address public oracle;

  mapping(address => Config) public tokenConfig;

  function initialize(
    address _oracle,
    address _baseStable,
    address _usd
  ) public initializer {
    OwnableUpgradeable.__Ownable_init();
    oracle = _oracle;
    baseStable = _baseStable;
    usd = _usd;
  }

  /// @notice Perform the conversion from LP to dollar
  /// @dev convert lpToDollar using chainlink oracle price
  /// @param _lpAmount in ether format
  /// @param _lpToken address of LP token
  function lpToDollar(uint256 _lpAmount, address _lpToken) external view returns (uint256, uint256) {
    if (_lpAmount == 0) {
      return (0, block.timestamp);
    }
    (uint256 _lpPrice, uint256 _lastUpdate) = _getLPPrice(_lpToken);
    return ((_lpAmount * _lpPrice) / (10**18), _lastUpdate);
  }

  /// @notice Perform the conversion from dollar to LP
  /// @dev convert dollartoLp using chainlink oracle price
  /// @param _dollarAmount in ether format
  /// @param _lpToken address of LP token
  function dollarToLp(uint256 _dollarAmount, address _lpToken) external view returns (uint256, uint256) {
    if (_dollarAmount == 0) {
      return (0, block.timestamp);
    }
    (uint256 _lpPrice, uint256 _lastUpdate) = _getLPPrice(_lpToken);
    return (((_dollarAmount * (10**18)) / _lpPrice), _lastUpdate);
  }

  /// @notice Get token price in dollar
  /// @dev getTokenPrice from address
  /// @param _tokenAddress tokenAddress
  function getTokenPrice(address _tokenAddress) external view returns (uint256 _price, uint256 _lastTimestamp) {
    (_price, _lastTimestamp) = _getTokenPrice(_tokenAddress);
  }

  /// @notice Check token price from dex and oracle is in the acceptable range
  /// @param _tokenAddress tokenAddress
  function isStable(address _tokenAddress) external view returns (bool) {
    (uint256 _price, ) = _getTokenPrice(_tokenAddress);
    return _isStable(_tokenAddress, _price);
  }

  function _isStable(address _tokenAddress, uint256 _oraclePrice) internal view returns (bool) {
    uint256[] memory _amounts = IRouterLike(tokenConfig[_tokenAddress].router).getAmountsOut(
      1e18,
      tokenConfig[_tokenAddress].path
    );

    uint256 _dexPrice = _amounts[_amounts.length - 1];

    // TODO: check when baseStable depeg with oracle
    if (
      _dexPrice * 10000 > _oraclePrice * tokenConfig[_tokenAddress].maxPriceDiff ||
      _dexPrice * tokenConfig[_tokenAddress].maxPriceDiff >= _oraclePrice * 10000
    ) {
      revert AlpacaV2Oracle_PriceTooDeviate(_dexPrice, _oraclePrice);
    }
    return true;
  }

  function _getTokenPrice(address _tokenAddress) internal view returns (uint256 _price, uint256 _lastTimestamp) {
    (_price, _lastTimestamp) = IPriceOracle(oracle).getPrice(_tokenAddress, usd);
    _isStable(_tokenAddress, _price);
  }

  /// @notice Set oracle
  /// @dev Set oracle address. Must be called by owner.
  /// @param _oracle oracle address
  function setOracle(address _oracle) external onlyOwner {
    if (_oracle == address(0)) revert AlpacaV2Oracle_InvalidOracleAddress();

    oracle = _oracle;

    emit LogSetOracle(msg.sender, _oracle);
  }

  /// @notice get LP price using internal only, return value in 1e18 format
  /// @dev getTokenPrice from address
  /// @param _lpToken lp token address
  function _getLPPrice(address _lpToken) internal view returns (uint256, uint256) {
    if (_lpToken == address(0)) {
      revert AlpacaV2Oracle_InvalidLPAddress();
    }
    uint256 _sqrtK;
    {
      uint256 _totalSupply = ILiquidityPair(_lpToken).totalSupply();
      if (_totalSupply == 0) {
        return (0, block.timestamp);
      }
      (uint256 _r0, uint256 _r1, ) = ILiquidityPair(_lpToken).getReserves();
      _sqrtK = LibFullMath.sqrt(_r0 * _r1).fdiv(_totalSupply); //fdiv return in 2**112
    }

    (uint256 _px0, uint256 _px1, uint8 _d0, uint8 _d1, uint256 _olderLastUpdate) = _px(_lpToken);

    // fair token0 amt: _sqrtK * sqrt(_px1/_px0)
    // fair token1 amt: _sqrtK * sqrt(_px0/_px1)
    // fair lp price = 2 * sqrt(_px0 * _px1)
    // split into 2 sqrts multiplication to prevent uint overflow (note the 2**112)

    uint256 _totalValueIn18;
    {
      uint8 padDecimals = 36 - (_d0 + _d1);
      uint256 _totalValue = (((_sqrtK * 2 * (LibFullMath.sqrt(_px0))) / (2**56)) * (LibFullMath.sqrt(_px1))) / (2**56);
      _totalValueIn18 = (_totalValue / (2**112)) * 10**(padDecimals); // revert bumped up 2*112 from fdiv() and convert price to 1e18 unit
    }

    return (_totalValueIn18, _olderLastUpdate);
  }

  /// @notice Return token prices, token decimals, oldest price update of given lptoken
  /// @param _lpToken lp token address
  function _px(address _lpToken)
    internal
    view
    returns (
      uint256,
      uint256,
      uint8,
      uint8,
      uint256
    )
  {
    address _token0Address = ILiquidityPair(_lpToken).token0();
    address _token1Address = ILiquidityPair(_lpToken).token1();

    (uint256 _p0, uint256 _p0LastUpdate) = _getTokenPrice(_token0Address); // in 2**112
    (uint256 _p1, uint256 _p1LastUpdate) = _getTokenPrice(_token1Address); // in 2**112

    uint256 _olderLastUpdate = _p0LastUpdate > _p1LastUpdate ? _p1LastUpdate : _p0LastUpdate;

    uint8 _d0 = IERC20(_token0Address).decimals();
    uint8 _d1 = IERC20(_token1Address).decimals();

    uint256 _px0 = (_p0 * (2**112)) / 10**(18 - _d0); // in token decimals * 2**112
    uint256 _px1 = (_p1 * (2**112)) / 10**(18 - _d1); // in token decimals * 2**112

    return (_px0, _px1, _d0, _d1, _olderLastUpdate);
  }

  function setTokenConfig(address[] calldata _tokens, Config[] calldata _configs) external onlyOwner {
    uint256 _len = _tokens.length;

    if (_len != _configs.length) {
      revert AlpacaV2Oracle_InvalidConfigLength();
    }

    address[] memory _path;
    for (uint256 _i = 0; _i < _len; ) {
      _path = _configs[_i].path;
      if (_path[_path.length - 1] != baseStable) {
        revert AlpacaV2Oracle_InvalidConfigPath();
      }

      tokenConfig[_tokens[_i]] = _configs[_i];

      unchecked {
        ++_i;
      }
    }
  }
}
