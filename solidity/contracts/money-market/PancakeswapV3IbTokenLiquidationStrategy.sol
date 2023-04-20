// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// ---- External Libraries ---- //
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// ---- Libraries ---- //
import { LibSafeToken } from "./libraries/LibSafeToken.sol";
import { LibShareUtil } from "./libraries/LibShareUtil.sol";
import { LibPath } from "./libraries/LibPath.sol";
import { LibPoolAddress } from "./libraries/LibPoolAddress.sol";

// ---- Interfaces ---- //
import { ILiquidationStrategy } from "./interfaces/ILiquidationStrategy.sol";
import { IInterestBearingToken } from "./interfaces/IInterestBearingToken.sol";
import { IV3SwapRouter } from "./interfaces/IV3SwapRouter.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { IMoneyMarket } from "./interfaces/IMoneyMarket.sol";
import { IPancakeV3Pool } from "./interfaces/IPancakeV3Pool.sol";
import { IPancakeV3Factory } from "./interfaces/IPancakeV3Factory.sol";

contract PancakeswapV3IbTokenLiquidationStrategy is ILiquidationStrategy, Ownable {
  using LibSafeToken for IERC20;
  using LibPath for bytes;

  error PancakeswapV3IbTokenLiquidationStrategy_Unauthorized();
  error PancakeswapV3IbTokenLiquidationStrategy_RepayTokenIsSameWithUnderlyingToken();
  error PancakeswapV3IbTokenLiquidationStrategy_PathConfigNotFound(address tokenIn, address tokenOut);
  error PancakeswapV3IbTokenLiquidationStrategy_NoLiquidity(address tokenA, address tokenB, uint24 fee);

  IV3SwapRouter internal immutable router;
  IMoneyMarket internal immutable moneyMarket;
  IPancakeV3Factory internal immutable pancakeV3Factory;

  mapping(address => bool) public callersOk;
  // tokenIn => tokenOut => path
  mapping(address => mapping(address => bytes)) public paths;

  /// @notice allow only whitelisted callers
  modifier onlyWhitelistedCallers() {
    if (!callersOk[msg.sender]) {
      revert PancakeswapV3IbTokenLiquidationStrategy_Unauthorized();
    }
    _;
  }

  constructor(
    address _router,
    address _moneyMarket,
    address _factory
  ) {
    router = IV3SwapRouter(_router);
    moneyMarket = IMoneyMarket(_moneyMarket);
    pancakeV3Factory = IPancakeV3Factory(_factory);
  }

  /// @notice Execute liquidate from collatToken to repayToken
  /// @param _ibToken The source token
  /// @param _repayToken The destination token
  /// @param _ibTokenAmountIn Available amount of source token to trade
  /// @param _minReceive Min token receive after swap
  function executeLiquidation(
    address _ibToken,
    address _repayToken,
    uint256 _ibTokenAmountIn,
    uint256, /*_repayAmount*/
    uint256 _minReceive
  ) external onlyWhitelistedCallers {
    // get underlying tokenAddress from MoneyMarket
    address _underlyingToken = moneyMarket.getTokenFromIbToken(_ibToken);

    // Revert if _underlyingToken and _repayToken are the same address
    if (_underlyingToken == _repayToken) {
      revert PancakeswapV3IbTokenLiquidationStrategy_RepayTokenIsSameWithUnderlyingToken();
    }

    bytes memory _path = paths[_underlyingToken][_repayToken];
    // Revert if no swapPath config for _underlyingToken and _repayToken pair
    if (_path.length == 0) {
      revert PancakeswapV3IbTokenLiquidationStrategy_PathConfigNotFound(_underlyingToken, _repayToken);
    }

    // withdraw ibToken from Moneymarket for underlyingToken
    uint256 _withdrawnUnderlyingAmount = moneyMarket.withdraw(msg.sender, _ibToken, _ibTokenAmountIn);

    // setup params from swap
    IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter.ExactInputParams({
      path: _path,
      recipient: msg.sender,
      amountIn: _withdrawnUnderlyingAmount,
      amountOutMinimum: _minReceive
    });

    // approve router for swapping
    IERC20(_underlyingToken).safeApprove(address(router), _withdrawnUnderlyingAmount);
    // swap ib's underlyingToken to repayToken
    router.exactInput(params);
    // reset approval
    IERC20(_underlyingToken).safeApprove(address(router), 0);
  }

  /// @notice Set paths config to be used during swap step in executeLiquidation
  /// @param _paths Array of parameters used to set path
  function setPaths(bytes[] calldata _paths) external onlyOwner {
    uint256 _len = _paths.length;
    for (uint256 _i; _i < _len; ) {
      bytes memory _path = _paths[_i];

      while (true) {
        bool hasMultiplePools = LibPath.hasMultiplePools(_path);

        // encoded hop (token0, fee, token1)
        bytes memory hop = _path.getFirstPool();
        // extract the token from encoded hop
        (address _token0, address _token1, uint24 _fee) = hop.decodeFirstPool();
        // get pool
        address _pool = pancakeV3Factory.getPool(_token0, _token1, _fee);

        // revrt if liquidity less than 0
        if (IPancakeV3Pool(_pool).liquidity() == 0) {
          revert PancakeswapV3IbTokenLiquidationStrategy_NoLiquidity(_token0, _token1, _fee);
        }

        // if true, go to the next hop
        if (hasMultiplePools) {
          _path = _path.skipToken();
        } else {
          // if it's last hop
          // Get source token address from first hop
          (address _source, , ) = _paths[_i].decodeFirstPool();
          // Get destination token from last hop
          (, address _destination, ) = _path.decodeFirstPool();
          // Assign to global paths
          paths[_source][_destination] = _paths[_i];
          break;
        }
      }

      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Set callers ok
  /// @param _callers A list of caller addresses
  /// @param _isOk An ok flag
  function setCallersOk(address[] calldata _callers, bool _isOk) external onlyOwner {
    uint256 _length = _callers.length;
    for (uint256 _i; _i < _length; ) {
      callersOk[_callers[_i]] = _isOk;
      unchecked {
        ++_i;
      }
    }
  }
}