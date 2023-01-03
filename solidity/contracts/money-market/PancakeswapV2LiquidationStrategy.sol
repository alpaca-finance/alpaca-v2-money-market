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

  error PancakeswapV2LiquidationStrategy_InvalidPath();
  error PancakeswapV2LiquidationStrategy_Unauthorized();

  IPancakeRouter02 internal router;

  mapping(address => bool) public callersOk;

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
  /// @param _repayAmount Exact destination token amount
  /// @param _repayTo The address to transfer destination token to
  /// @param _data Extra calldata information
  function executeLiquidation(
    address _collatToken,
    address _repayToken,
    uint256 _repayAmount,
    address _repayTo,
    bytes calldata _data
  ) external onlyWhitelistedCallers {
    (address[] memory path, uint256 _minReceive) = abi.decode(_data, (address[], uint256));
    if (path[0] != _collatToken || path[path.length - 1] != _repayToken) {
      revert PancakeswapV2LiquidationStrategy_InvalidPath();
    }

    uint256 _collatBalance = IERC20(_collatToken).balanceOf(address(this));

    IERC20(_collatToken).safeApprove(address(router), _collatBalance);

    uint256[] memory _amountsIn = router.getAmountsIn(_repayAmount, path);
    // _amountsIn[0] = collat that is required to swap for _repayAmount
    if (_collatBalance >= _amountsIn[0]) {
      // swapTokensForExactTokens will fail if _collatBalance is not enough to swap for _repayAmount during low liquidity period
      router.swapTokensForExactTokens(_repayAmount, _collatBalance, path, _repayTo, block.timestamp);
    } else {
      router.swapExactTokensForTokens(_collatBalance, _minReceive, path, _repayTo, block.timestamp);
    }

    IERC20(_collatToken).safeApprove(address(router), 0);

    uint256 _remainCollat = IERC20(_collatToken).balanceOf(address(this));

    if (_remainCollat > 0) {
      IERC20(_collatToken).safeTransfer(_repayTo, _remainCollat);
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
