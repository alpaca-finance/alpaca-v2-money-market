// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// ---- External Libraries ---- //
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// ---- Libraries ---- //
import { LibSafeToken } from "./libraries/LibSafeToken.sol";
import { LibPath } from "./libraries/LibPath.sol";

// ---- Interfaces ---- //
import { ILiquidationStrategy } from "./interfaces/ILiquidationStrategy.sol";
import { IPancakeSwapRouterV3 } from "./interfaces/IPancakeSwapRouterV3.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { IPancakeV3Pool } from "./interfaces/IPancakeV3Pool.sol";
import { IUniSwapV3PathReader } from "../reader/interfaces/IUniSwapV3PathReader.sol";

contract PancakeswapV3TokenLiquidationStrategy is ILiquidationStrategy, Ownable {
  using LibSafeToken for IERC20;
  using LibPath for bytes;

  event LogSetCaller(address _caller, bool _isOk);
  event LogSetPath(address _token0, address _token1, bytes _path);

  error PancakeswapV3TokenLiquidationStrategy_Unauthorized();
  error PancakeswapV3TokenLiquidationStrategy_RepayTokenIsSameWithCollatToken();
  error PancakeswapV3TokenLiquidationStrategy_PathConfigNotFound(address tokenIn, address tokenOut);
  error PancakeswapV3TokenLiquidationStrategy_NoLiquidity(address tokenA, address tokenB, uint24 fee);

  IPancakeSwapRouterV3 internal immutable router;
  IUniSwapV3PathReader public pathReader;

  address internal constant PANCAKE_V3_POOL_DEPLOYER = 0x41ff9AA7e16B8B1a8a8dc4f0eFacd93D02d071c9;
  bytes32 internal constant POOL_INIT_CODE_HASH = 0x6ce8eb472fa82df5469c6ab6d485f17c3ad13c8cd7af59b3d4a8026c5ce0f7e2;

  mapping(address => bool) public callersOk;
  // tokenIn => tokenOut => path
  mapping(address => mapping(address => bytes)) public paths;

  struct WithdrawParam {
    address to;
    address token;
    uint256 amount;
  }

  /// @notice allow only whitelisted callers
  modifier onlyWhitelistedCallers() {
    if (!callersOk[msg.sender]) {
      revert PancakeswapV3TokenLiquidationStrategy_Unauthorized();
    }
    _;
  }

  constructor(address _router, address _pathReader) {
    router = IPancakeSwapRouterV3(_router);
    pathReader = IUniSwapV3PathReader(_pathReader);
  }

  /// @notice Execute liquidate from collatToken to repayToken
  /// @param _collatToken The source token
  /// @param _repayToken The destination token
  /// @param _collatAmountIn Available amount of source token to trade
  /// @param _minReceive Min token receive after swap
  function executeLiquidation(
    address _collatToken,
    address _repayToken,
    uint256 _collatAmountIn,
    uint256, /* _repayAmount */
    uint256 _minReceive
  ) external onlyWhitelistedCallers {
    // Revert if _underlyingToken and _repayToken are the same address
    if (_collatToken == _repayToken) {
      revert PancakeswapV3TokenLiquidationStrategy_RepayTokenIsSameWithCollatToken();
    }

    bytes memory _path = pathReader.paths(_collatToken, _repayToken);
    // Revert if no swapPath config for _collatToken and _repayToken pair
    if (_path.length == 0) {
      revert PancakeswapV3TokenLiquidationStrategy_PathConfigNotFound(_collatToken, _repayToken);
    }

    // setup params from swap
    IPancakeSwapRouterV3.ExactInputParams memory params = IPancakeSwapRouterV3.ExactInputParams({
      path: _path,
      recipient: msg.sender,
      deadline: block.timestamp,
      amountIn: _collatAmountIn,
      amountOutMinimum: _minReceive
    });

    // approve router for swapping
    IERC20(_collatToken).safeApprove(address(router), _collatAmountIn);
    // swap all collatToken to repayToken
    router.exactInput(params);
  }

  /// @notice Set callers ok
  /// @param _callers A list of caller addresses
  /// @param _isOk An ok flag
  function setCallersOk(address[] calldata _callers, bool _isOk) external onlyOwner {
    uint256 _length = _callers.length;
    for (uint256 _i; _i < _length; ) {
      callersOk[_callers[_i]] = _isOk;
      emit LogSetCaller(_callers[_i], _isOk);
      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Withdraw ERC20 from this contract
  /// @param _withdrawParams an array of Withdrawal parameters (to, token, amount)
  function withdraw(WithdrawParam[] calldata _withdrawParams) external onlyOwner {
    uint256 _length = _withdrawParams.length;
    for (uint256 _i; _i < _length; ) {
      IERC20(_withdrawParams[_i].token).safeTransfer(_withdrawParams[_i].to, _withdrawParams[_i].amount);

      unchecked {
        ++_i;
      }
    }
  }
}
