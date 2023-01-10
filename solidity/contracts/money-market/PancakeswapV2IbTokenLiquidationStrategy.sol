// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// ---- External Libraries ---- //
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// ---- Libraries ---- //
import { LibSafeToken } from "./libraries/LibSafeToken.sol";
import { LibShareUtil } from "./libraries/LibShareUtil.sol";

// ---- Interfaces ---- //
import { ILiquidationStrategy } from "./interfaces/ILiquidationStrategy.sol";
import { IPancakeRouter02 } from "../lyf/interfaces/IPancakeRouter02.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { IMoneyMarket } from "./interfaces/IMoneyMarket.sol";

contract PancakeswapV2IbTokenLiquidationStrategy is ILiquidationStrategy, Ownable {
  using LibSafeToken for IERC20;

  error PancakeswapV2IbTokenLiquidationStrategy_Unauthorized();
  error PancakeswapV2IbTokenLiquidationStrategy_InvalidIbToken(address _ibToken);
  error PancakeswapV2IbTokenLiquidationStrategy_PathConfigNotFound(address tokenIn, address tokenOut);

  struct SetPathParams {
    address[] path;
  }

  IPancakeRouter02 internal router;
  IMoneyMarket internal moneyMarket;

  mapping(address => bool) public callersOk;
  // tokenIn => tokenOut => path
  mapping(address => mapping(address => address[])) public paths;

  /// @notice require that only allowed callers
  modifier onlyWhitelistedCallers() {
    if (!callersOk[msg.sender]) {
      revert PancakeswapV2IbTokenLiquidationStrategy_Unauthorized();
    }
    _;
  }

  constructor(address _router, address _moneyMarket) {
    router = IPancakeRouter02(_router);
    moneyMarket = IMoneyMarket(_moneyMarket);
  }

  /// @notice Execute liquidate from collatToken to repayToken
  /// @param _ibToken The source token
  /// @param _repayToken The destination token
  /// @param _ibTokenIn Available amount of source token to trade
  /// @param _repayAmount Exact destination token amount
  /// @param _data Extra calldata information
  function executeLiquidation(
    address _ibToken,
    address _repayToken,
    uint256 _ibTokenIn,
    uint256 _repayAmount,
    bytes calldata _data
  ) external onlyWhitelistedCallers {
    // check ib token should open market
    address _underlyingToken = moneyMarket.getTokenFromIbToken(_ibToken);
    if (_underlyingToken == address(0)) {
      revert PancakeswapV2IbTokenLiquidationStrategy_InvalidIbToken(_ibToken);
    }

    uint256 _minReceive = abi.decode(_data, (uint256));
    address[] memory _path = paths[_underlyingToken][_repayToken];
    if (_path.length == 0) {
      revert PancakeswapV2IbTokenLiquidationStrategy_PathConfigNotFound(_underlyingToken, _repayToken);
    }

    uint256 _ibTokenBalanceBefore = IERC20(_ibToken).balanceOf(address(this)) - _ibTokenIn;
    // _amountsIn[0] = collat that is required to swap for _repayAmount
    uint256[] memory _amountsIn = router.getAmountsIn(_repayAmount, _path);

    // to withdraw
    {
      uint256 _requireAmountToWithdraw = LibShareUtil.valueToShare(
        _amountsIn[0],
        IERC20(_ibToken).totalSupply(),
        moneyMarket.getTotalTokenWithPendingInterest(_underlyingToken)
      );

      uint256 _actualAmountToWithdraw = _ibTokenIn > _requireAmountToWithdraw ? _requireAmountToWithdraw : _ibTokenIn;

      IERC20(_ibToken).safeIncreaseAllowance(address(moneyMarket), _actualAmountToWithdraw);
      uint256 _withdrawalAmount = moneyMarket.withdraw(_ibToken, _actualAmountToWithdraw);

      IERC20(_underlyingToken).safeIncreaseAllowance(address(router), _withdrawalAmount);
      if (_withdrawalAmount >= _amountsIn[0]) {
        // swapTokensForExactTokens will fail if _collatAmountIn is not enough to swap for _repayAmount during low liquidity period
        router.swapTokensForExactTokens(_repayAmount, _withdrawalAmount, _path, msg.sender, block.timestamp);
      } else {
        router.swapExactTokensForTokens(_withdrawalAmount, _minReceive, _path, msg.sender, block.timestamp);
      }
    }

    // transfer back if ibToken has in contract
    uint256 _ibTokenBalanceAfter = IERC20(_ibToken).balanceOf(address(this));
    if (_ibTokenBalanceAfter > _ibTokenBalanceBefore) {
      IERC20(_ibToken).safeTransfer(msg.sender, _ibTokenBalanceAfter - _ibTokenBalanceBefore);
    }
  }

  /// @notice Set paths config to be used during swap step in executeLiquidation
  /// @param _inputs Array of parameters used to set path
  function setPaths(SetPathParams[] calldata _inputs) external onlyOwner {
    uint256 _len = _inputs.length;
    for (uint256 _i = 0; _i < _len; ) {
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
    for (uint256 _i = 0; _i < _length; ) {
      callersOk[_callers[_i]] = _isOk;
      unchecked {
        ++_i;
      }
    }
  }
}
