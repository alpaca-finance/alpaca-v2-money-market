// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// ---- External Libraries ---- //
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// ---- Libraries ---- //
import { LibSafeToken } from "./libraries/LibSafeToken.sol";

// ---- Interfaces ---- //
import { ILiquidationStrategy } from "./interfaces/ILiquidationStrategy.sol";
import { IPancakeRouter02 } from "../lyf/interfaces/IPancakeRouter02.sol";
import { IERC20 } from "./interfaces/IERC20.sol";

contract PancakeswapV2LiquidationStrategy is ILiquidationStrategy, Ownable {
  using LibSafeToken for IERC20;

  error PancakeswapV2LiquidationStrategy_Unauthorized();
  error PancakeswapV2LiquidationStrategy_PathConfigNotFound(address tokenIn, address tokenOut);
  error PancakeswapV2LiquidationStrategy_InvalidSetPathParams();

  struct SetPathParams {
    address tokenIn;
    address tokenOut;
    address[] path;
  }

  IPancakeRouter02 internal router;

  mapping(address => bool) public callersOk;
  mapping(address => mapping(address => address[])) public paths;

  /// @notice require that only allowed callers
  modifier onlyWhitelistedCallers() {
    if (!callersOk[msg.sender]) {
      revert PancakeswapV2LiquidationStrategy_Unauthorized();
    }
    _;
  }

  constructor(address _router) {
    router = IPancakeRouter02(_router);
  }

  /// @notice Execute liquidate from collatToken to repayToken
  /// @param _collatToken The source token
  /// @param _repayToken The destination token
  /// @param _collatAmountIn Available amount of source token to trade
  /// @param _repayAmount Exact destination token amount
  /// @param _data Extra calldata information
  function executeLiquidation(
    address _collatToken,
    address _repayToken,
    uint256 _collatAmountIn,
    uint256 _repayAmount,
    bytes calldata _data
  ) external onlyWhitelistedCallers {
    uint256 _minReceive = abi.decode(_data, (uint256));
    address[] memory _path = paths[_collatToken][_repayToken];

    if (_path.length == 0) {
      revert PancakeswapV2LiquidationStrategy_PathConfigNotFound(_collatToken, _repayToken);
    }

    IERC20(_collatToken).safeApprove(address(router), _collatAmountIn);

    uint256[] memory _amountsIn = router.getAmountsIn(_repayAmount, _path);
    // _amountsIn[0] = collat that is required to swap for _repayAmount
    if (_collatAmountIn >= _amountsIn[0]) {
      // swapTokensForExactTokens will fail if _collatAmountIn is not enough to swap for _repayAmount during low liquidity period
      router.swapTokensForExactTokens(_repayAmount, _collatAmountIn, _path, msg.sender, block.timestamp);
      IERC20(_collatToken).safeTransfer(msg.sender, _collatAmountIn - _amountsIn[0]);
    } else {
      router.swapExactTokensForTokens(_collatAmountIn, _minReceive, _path, msg.sender, block.timestamp);
    }

    IERC20(_collatToken).safeApprove(address(router), 0);
  }

  /// @notice Set paths config to be used during swap step in executeLiquidation
  /// @param _inputs Array of parameters used to set path
  function setPaths(SetPathParams[] calldata _inputs) external onlyOwner {
    uint256 len = _inputs.length;
    for (uint256 i = 0; i < len; ) {
      SetPathParams memory _params = _inputs[i];
      address[] memory _path = _params.path;

      if (_params.tokenIn != _path[0] || _params.tokenOut != _path[_path.length - 1]) {
        revert PancakeswapV2LiquidationStrategy_InvalidSetPathParams();
      }
      // sanity check. router will revert if pair doesn't exist
      router.getAmountsIn(1 ether, _path);

      paths[_params.tokenIn][_params.tokenOut] = _path;

      unchecked {
        ++i;
      }
    }
  }

  /// @notice Set callers ok
  /// @param _callers A list of caller addresses
  /// @param _isOk An ok flag
  function setCallersOk(address[] calldata _callers, bool _isOk) external onlyOwner {
    uint256 _length = _callers.length;
    for (uint256 _i = 0; _i < _length; ) {
      callersOk[_callers[_i]] = _isOk;
      unchecked {
        ++_i;
      }
    }
  }
}
