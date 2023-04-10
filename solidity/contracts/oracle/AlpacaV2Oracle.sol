// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// ---- External Libraries ---- //
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// ---- Libraries ---- //
import { LibFullMath } from "./libraries/LibFullMath.sol";

// ---- Interfaces ---- //
import { ILiquidityPair } from "./interfaces/ILiquidityPair.sol";
import { IAlpacaV2Oracle } from "./interfaces/IAlpacaV2Oracle.sol";
import { IPriceOracle } from "./interfaces/IPriceOracle.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { IRouterLike } from "./interfaces/IRouterLike.sol";
import { IUniswapV3Pool } from "./interfaces/IUniswapV3Pool.sol";

contract AlpacaV2Oracle is IAlpacaV2Oracle, Ownable {
  using LibFullMath for uint256;

  // Events
  event LogSetOracle(address indexed _caller, address _newOracle);
  event LogSetTokenConfig(
    address indexed _caller,
    address indexed _token,
    address _router,
    address[] _path,
    uint64 _maxPriceDiffBps,
    bool _isUsingV3Pool
  );
  event LogSetPool(
    address indexed _caller,
    address indexed _source,
    address indexed _destination,
    address _poolAddress
  );

  uint256 internal constant MAX_BPS = 10000;

  // An address of chainlink usd token
  address public immutable usd;

  // Stabletoken to compare value
  address public immutable baseStable;

  // a OracleMedianizer interface to perform get price
  address public oracle;

  // mapping of token to tokenConfig
  mapping(address => Config) public tokenConfigs;

  // mapping of uniswap v3 pool address
  //  source => destination => poolAddress
  mapping(address => mapping(address => address)) public v3PoolAddreses;

  constructor(
    address _oracle,
    address _baseStable,
    address _usd
  ) {
    // Revert if baseStable token doesn't have 18 decimal
    if (IERC20(_baseStable).decimals() != 18) {
      revert AlpacaV2Oracle_InvalidBaseStableTokenDecimal();
    }

    // sanity call
    IPriceOracle(_oracle).getPrice(_baseStable, _usd);

    oracle = _oracle;
    baseStable = _baseStable;
    usd = _usd;
  }

  /// @notice Perform the conversion from LP to dollar
  /// @dev convert lpToDollar using chainlink oracle price
  /// @param _lpAmount in ether format
  /// @param _lpToken address of LP token
  function lpToDollar(uint256 _lpAmount, address _lpToken) external view returns (uint256, uint256) {
    // if _lpAmount = 0 no need to convert
    if (_lpAmount == 0) {
      return (0, block.timestamp);
    }

    // get lp fair price and oldest _lastUpdate between token0 and token1
    (uint256 _lpPrice, uint256 _lastUpdate) = _getLPPrice(_lpToken);

    return ((_lpAmount * _lpPrice) / (10**18), _lastUpdate);
  }

  /// @notice Perform the conversion from dollar to LP
  /// @dev convert dollartoLp using chainlink oracle price
  /// @param _dollarAmount in ether format
  /// @param _lpToken address of LP token
  function dollarToLp(uint256 _dollarAmount, address _lpToken) external view returns (uint256, uint256) {
    // if _dollarAmount = 0 no need to convert
    if (_dollarAmount == 0) {
      return (0, block.timestamp);
    }
    // get lp fair price and oldest _lastUpdate between token0 and token1
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
  function isStable(address _tokenAddress) external view {
    _getTokenPrice(_tokenAddress);
  }

  /// @dev validate price stability of token. Check token price from oracle against dex.
  ///      It is unstable if prices of oracle and dex deviate too much
  /// @param _tokenAddress address of token
  /// @param _oraclePrice token price from oracleMedianizer
  function _validateStability(address _tokenAddress, uint256 _oraclePrice) internal view {
    // if _tokenAddress is baseStable no need to validate
    if (_tokenAddress == baseStable) {
      return;
    }

    Config memory _tokenConfig = tokenConfigs[_tokenAddress];
    // get baseStable price usd from OracleMedianizer
    (uint256 _basePrice, ) = IPriceOracle(oracle).getPrice(baseStable, usd);

    uint256 _dexPrice;

    if (_tokenConfig.isUsingV3Pool) {
      // calulating _dexPrice of token (v3)
      // product of price in each pool that need to hop through the path
      // example:
      // - path = [BTC, ETH, USDT]
      // - pool1 = BTC/ETH, price = 15
      // - pool2 = ETH/USDT, price = 1850
      // _dexPrice = 15 * 1850 = 27750
      _dexPrice = 1;
      for (uint256 i = 0; i < _tokenConfig.path.length - 1; ) {
        _dexPrice = (_dexPrice * _getPriceFromV3Pool(_tokenConfig.path[i], _tokenConfig.path[i + 1]));
        unchecked {
          i++;
        }
      }
    } else {
      // call router for getting swap rate between token and baseStableToken
      uint256[] memory _amounts = IRouterLike(_tokenConfig.router).getAmountsOut(
        10**IERC20(_tokenAddress).decimals(),
        _tokenConfig.path
      );

      // calculating _dexPrice of token (v2)
      // example:
      // - swapRate = 300, _basePrice = 1.01
      // _dexPrice = swapRate * basePrice = 300 * 1.01 = 303
      _dexPrice =
        (_amounts[_amounts.length - 1] * _basePrice) /
        10**IERC20(_tokenConfig.path[_tokenConfig.path.length - 1]).decimals();
    }

    // example of unstable price:
    //  - maxPriceDiffBps = 10500

    // case1: price too high
    //  - oraclePrice = 300, dexPrice = 330
    //  330 * 10000 > 300 * 10500
    //  3300000 > 3150000

    // case2: price too low
    //  - oraclePrice = 300, dexPrice = 270
    //  270 * 10500 < 300 * 10000
    //  2835000 < 3000000

    // _dexPrice/_oraclePrice > maxPriceDiffBps/10000
    // _dexPrice/_oraclePrice < 10000/maxPriceDiffBps
    uint256 _maxPriceDiff = tokenConfigs[_tokenAddress].maxPriceDiffBps;
    if (_dexPrice * MAX_BPS > _oraclePrice * _maxPriceDiff || _dexPrice * _maxPriceDiff < _oraclePrice * MAX_BPS) {
      revert AlpacaV2Oracle_PriceTooDeviate(_dexPrice, _oraclePrice);
    }
  }

  /// @dev get price of token in usd, will revert if price is not stable
  /// @param _tokenAddress address of token
  function _getTokenPrice(address _tokenAddress) internal view returns (uint256 _price, uint256 _lastTimestamp) {
    (_price, _lastTimestamp) = IPriceOracle(oracle).getPrice(_tokenAddress, usd);
    _validateStability(_tokenAddress, _price);
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
  /// @return _totalValueIn18 value of lpToken in dollar
  /// @return _olderLastUpdate older price update between token0 and token1 of LP
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

  /// @notice Set token configuration
  /// @param _tokens List of token to set config
  /// @param _configs List of tokenConfig
  function setTokenConfig(address[] calldata _tokens, Config[] calldata _configs) external onlyOwner {
    uint256 _len = _tokens.length;

    // Revert if array length mismatch
    if (_len != _configs.length) {
      revert AlpacaV2Oracle_InvalidConfigLength();
    }

    address[] memory _path;
    for (uint256 _i; _i < _len; ) {
      _path = _configs[_i].path;

      // Validate swap path correctness
      // Revert if swap path < 2
      // Revert if source is not input token
      // Revert if destination is not baseStable
      if (_path.length < 2 || _path[0] != _tokens[_i] || _path[_path.length - 1] != baseStable) {
        revert AlpacaV2Oracle_InvalidConfigPath();
      }

      // Revert if maxPriceDiffBps < MAX_BPS
      if (_configs[_i].maxPriceDiffBps < MAX_BPS) {
        revert AlpacaV2Oracle_InvalidPriceDiffConfig();
      }

      tokenConfigs[_tokens[_i]] = _configs[_i];

      emit LogSetTokenConfig(
        msg.sender,
        _tokens[_i],
        _configs[_i].router,
        _configs[_i].path,
        _configs[_i].maxPriceDiffBps,
        _configs[_i].isUsingV3Pool
      );

      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Set pool address of uniswap v3
  /// @param _source source token address
  /// @param _destination destination token address
  /// @param _pool uniswap v3 pool
  function setPool(
    address _source,
    address _destination,
    IUniswapV3Pool _pool
  ) external onlyOwner {
    // verify that pool contain both source and destination token
    if (
      !(_pool.token0() == _source && _pool.token1() == _destination) ||
      !(_pool.token0() == _destination && _pool.token1() == _source)
    ) {
      revert AlpacaV2Oracle_InvalidPool();
    }

    address _poolAddress = address(_pool);
    v3PoolAddreses[_source][_destination] = _poolAddress;
    emit LogSetPool(msg.sender, _source, _destination, _poolAddress);
  }

  /// @notice Get price from uniswap v3 pool
  /// @dev To verify in fork test
  /// @param _source source token address
  /// @param _destination destination token address
  /// @return _price price in 1e18
  function getPriceFromV3Pool(address _source, address _destination) external view returns (uint256 _price) {
    _price = _getPriceFromV3Pool(_source, _destination);
  }

  /// @dev Get price in 1e18 from uniswap v3 pool with last update timestamp
  /// @param _source source token address
  /// @param _destination destination token address
  function _getPriceFromV3Pool(address _source, address _destination) internal view returns (uint256 _price) {
    // assume that pool address is correct since it was verified when setPool
    address _poolAddress = v3PoolAddreses[_source][_destination];
    IUniswapV3Pool _pool = IUniswapV3Pool(_poolAddress);

    // get sqrtPriceX96 from uniswap v3 pool
    (uint160 _sqrtPriceX96, , , , , , ) = _pool.slot0();

    // calculation
    // - _sqrtPriceIn1e18 = sqrtX96 * 1e18 / 2**96
    // - _non18Price = _sqrtPriceIn1e18 ** 2 / 1e18
    // - priceIn18QuoteByToken1 = _non18Price * 10**token0Decimal / 10**token1Decimal
    //
    // example:
    // - source = USDC, destination = ETH
    // - token0 = USDC, token1 = ETH
    // - sqrtPriceX96 = 1839650835463716126473692777239695
    //
    // _sqrtPriceIn1e18 = 1839650835463716126473692777239695 * 1e18 / 2**96 = 2.3219657973671966e+22
    // _non18Price = 2.3219657973671966e+22 ** 2 / 1e18 = 5.391525164143081e+26
    // priceIn18QuoteByToken1 = 5.391525164143081e+26 * 10**6 / 10**18 = 539152516414308 (in 1e18 unit)
    //                        = 0.00054 ETH/USDC

    uint256 _sqrtPriceIn1e18 = LibFullMath.mulDiv(uint256(_sqrtPriceX96), 10**18, 1 << 96);
    uint256 _non18Price = LibFullMath.mulDiv(_sqrtPriceIn1e18, _sqrtPriceIn1e18, 1e18);
    _price = LibFullMath.mulDiv(
      _non18Price,
      10**(IERC20(_pool.token0()).decimals()),
      10**(IERC20(_pool.token1()).decimals())
    );

    // if source token is token0, then price is sqrtPriceX96, otherwise price is inverse of sqrtPriceX96
    if (_source > _destination) {
      // use 1e36 to avoid underflow and keep unit in 1e18
      //
      // calculation:
      // - priceIn18QuoteByToken0 = 1e36 / priceIn18QuoteByToken1
      //
      // example:
      // - source = ETH, destination = USDC
      // - token0 = USDC, token1 = ETH
      // - priceIn18QuoteByToken1 = 539152516414308
      // - priceIn18QuoteByToken0 = 1e36 / 539152516414308 = 1854762742554941500000 (in 1e18 unit)
      //                          = 1854.76274 USDC/ETH
      _price = 10**36 / _price;
    }
  }
}
