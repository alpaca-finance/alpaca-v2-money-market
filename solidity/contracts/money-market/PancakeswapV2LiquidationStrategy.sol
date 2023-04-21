// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// ---- External Libraries ---- //
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// ---- Libraries ---- //
import { LibSafeToken } from "./libraries/LibSafeToken.sol";

// ---- Interfaces ---- //
import { ILiquidationStrategy } from "./interfaces/ILiquidationStrategy.sol";
import { IPancakeRouter02 } from "./interfaces/IPancakeRouter02.sol";
import { IERC20 } from "./interfaces/IERC20.sol";

contract PancakeswapV2LiquidationStrategy is ILiquidationStrategy, Ownable {
  using LibSafeToken for IERC20;

  error PancakeswapV2LiquidationStrategy_Unauthorized();
  error PancakeswapV2LiquidationStrategy_PathConfigNotFound(address tokenIn, address tokenOut);

  struct SetPathParams {
    address[] path;
  }

  IPancakeRouter02 internal immutable router;

  mapping(address => bool) public callersOk;
  // tokenIn => tokenOut => path
  mapping(address => mapping(address => address[])) public paths;

  /// @notice allow only whitelisted callers
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
  /// @param _minReceive Min token receive after swap
  function executeLiquidation(
    address _collatToken,
    address _repayToken,
    uint256 _collatAmountIn,
    uint256 _repayAmount,
    uint256 _minReceive
  ) external onlyWhitelistedCallers {
    address[] memory _path = paths[_collatToken][_repayToken];

    // Revert if no swapPath config for _collatToken and _repayToken pair
    if (_path.length == 0) {
      revert PancakeswapV2LiquidationStrategy_PathConfigNotFound(_collatToken, _repayToken);
    }

    // approve router for swapping
    IERC20(_collatToken).safeApprove(address(router), _collatAmountIn);

    // _amountsIn[0] = collateral amount required to swap for _repayAmount
    uint256[] memory _amountsIn = router.getAmountsIn(_repayAmount, _path);

    if (_collatAmountIn > _amountsIn[0]) {
      // swap collateralToken to repayToken
      router.swapExactTokensForTokens(_amountsIn[0], _minReceive, _path, msg.sender, block.timestamp);
      // transfer remaining collateral back to caller
      IERC20(_collatToken).safeTransfer(msg.sender, _collatAmountIn - _amountsIn[0]);
    } else {
      // swap collateralToken to repayToken
      router.swapExactTokensForTokens(_collatAmountIn, _minReceive, _path, msg.sender, block.timestamp);
    }

    // reset approval
    IERC20(_collatToken).safeApprove(address(router), 0);
  }

  /// @notice Set paths config to be used during swap step in executeLiquidation
  /// @param _inputs Array of parameters used to set path
  function setPaths(SetPathParams[] calldata _inputs) external onlyOwner {
    uint256 _len = _inputs.length;
    for (uint256 _i; _i < _len; ) {
      SetPathParams memory _params = _inputs[_i];
      address[] memory _path = _params.path;

      // sanity check. router will revert if pair doesn't exist
      router.getAmountsIn(1 ether, _path);

      paths[_path[0]][_path[_path.length - 1]] = _path;

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
