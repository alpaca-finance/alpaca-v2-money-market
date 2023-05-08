// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// ---- External Libraries ---- //
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// ---- Libraries ---- //
import { LibSafeToken } from "./libraries/LibSafeToken.sol";

// ---- Interfaces ---- //
import { ILiquidationStrategy } from "./interfaces/ILiquidationStrategy.sol";
import { IPancakeSwapRouterV3 } from "./interfaces/IPancakeSwapRouterV3.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { IMoneyMarket } from "./interfaces/IMoneyMarket.sol";
import { IUniSwapV3PathReader } from "../reader/interfaces/IUniSwapV3PathReader.sol";

contract PancakeswapV3IbTokenLiquidationStrategy_WithPathReader is ILiquidationStrategy, Ownable {
  using LibSafeToken for IERC20;

  event LogSetCaller(address _caller, bool _isOk);

  error PancakeswapV3IbTokenLiquidationStrategy_Unauthorized();
  error PancakeswapV3IbTokenLiquidationStrategy_RepayTokenIsSameWithUnderlyingToken();
  error PancakeswapV3IbTokenLiquidationStrategy_PathConfigNotFound(address tokenIn, address tokenOut);

  IPancakeSwapRouterV3 internal immutable router;
  IMoneyMarket internal immutable moneyMarket;
  IUniSwapV3PathReader internal immutable pathReader;

  mapping(address => bool) public callersOk;

  struct WithdrawParam {
    address to;
    address token;
    uint256 amount;
  }

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
    address _pathReader
  ) {
    router = IPancakeSwapRouterV3(_router);
    moneyMarket = IMoneyMarket(_moneyMarket);
    pathReader = IUniSwapV3PathReader(_pathReader);
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

    bytes memory _path = pathReader.paths(_underlyingToken, _repayToken);
    // Revert if no swapPath config for _underlyingToken and _repayToken pair
    if (_path.length == 0) {
      revert PancakeswapV3IbTokenLiquidationStrategy_PathConfigNotFound(_underlyingToken, _repayToken);
    }

    // withdraw ibToken from Moneymarket for underlyingToken
    uint256 _withdrawnUnderlyingAmount = moneyMarket.withdraw(msg.sender, _ibToken, _ibTokenAmountIn);

    // setup params from swap
    IPancakeSwapRouterV3.ExactInputParams memory params = IPancakeSwapRouterV3.ExactInputParams({
      path: _path,
      recipient: msg.sender,
      deadline: block.timestamp,
      amountIn: _withdrawnUnderlyingAmount,
      amountOutMinimum: _minReceive
    });

    // approve router for swapping
    IERC20(_underlyingToken).safeApprove(address(router), _withdrawnUnderlyingAmount);
    // swap all ib's underlyingToken to repayToken
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
