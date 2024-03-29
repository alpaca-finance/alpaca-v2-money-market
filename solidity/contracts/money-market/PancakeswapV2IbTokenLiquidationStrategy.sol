// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// ---- External Libraries ---- //
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// ---- Libraries ---- //
import { LibSafeToken } from "./libraries/LibSafeToken.sol";
import { LibShareUtil } from "./libraries/LibShareUtil.sol";

// ---- Interfaces ---- //
import { ILiquidationStrategy } from "./interfaces/ILiquidationStrategy.sol";
import { IInterestBearingToken } from "./interfaces/IInterestBearingToken.sol";
import { IPancakeRouter02 } from "./interfaces/IPancakeRouter02.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { IMoneyMarket } from "./interfaces/IMoneyMarket.sol";

contract PancakeswapV2IbTokenLiquidationStrategy is ILiquidationStrategy, Ownable {
  using LibSafeToken for IERC20;

  error PancakeswapV2IbTokenLiquidationStrategy_Unauthorized();
  error PancakeswapV2IbTokenLiquidationStrategy_RepayTokenIsSameWithUnderlyingToken();
  error PancakeswapV2IbTokenLiquidationStrategy_PathConfigNotFound(address tokenIn, address tokenOut);

  struct SetPathParams {
    address[] path;
  }

  struct WithdrawParam {
    address to;
    address token;
    uint256 amount;
  }

  IPancakeRouter02 internal immutable router;
  IMoneyMarket internal immutable moneyMarket;

  mapping(address => bool) public callersOk;
  // tokenIn => tokenOut => path
  mapping(address => mapping(address => address[])) public paths;

  /// @notice allow only whitelisted callers
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
  /// @param _ibTokenAmountIn Available amount of source token to trade
  /// @param _repayAmount Exact destination token amount
  /// @param _minReceive Min token receive after swap
  function executeLiquidation(
    address _ibToken,
    address _repayToken,
    uint256 _ibTokenAmountIn,
    uint256 _repayAmount,
    uint256 _minReceive,
    bytes memory /* _data */
  ) external onlyWhitelistedCallers {
    // get underlying tokenAddress from MoneyMarket
    address _underlyingToken = moneyMarket.getTokenFromIbToken(_ibToken);

    // Revert if _underlyingToken and _repayToken are the same address
    if (_underlyingToken == _repayToken) {
      revert PancakeswapV2IbTokenLiquidationStrategy_RepayTokenIsSameWithUnderlyingToken();
    }

    address[] memory _path = paths[_underlyingToken][_repayToken];
    // Revert if no swapPath config for _underlyingToken and _repayToken pair
    if (_path.length == 0) {
      revert PancakeswapV2IbTokenLiquidationStrategy_PathConfigNotFound(_underlyingToken, _repayToken);
    }

    // Get the underlyingToken amount needed for swapping to repayToken
    uint256 _requiredUnderlyingAmount = _getRequiredUnderlyingAmount(_repayAmount, _path);

    // withdraw ibToken from Moneymarket for underlyingToken
    (uint256 _withdrawnIbTokenAmount, uint256 _withdrawnUnderlyingAmount) = _withdrawFromMoneyMarket(
      _ibToken,
      _ibTokenAmountIn,
      _requiredUnderlyingAmount
    );

    // approve router for swapping
    IERC20(_underlyingToken).safeApprove(address(router), _withdrawnUnderlyingAmount);
    // swap ib's underlyingToken to repayToken
    router.swapExactTokensForTokens(_withdrawnUnderlyingAmount, _minReceive, _path, msg.sender, block.timestamp);
    // reset approval
    IERC20(_underlyingToken).safeApprove(address(router), 0);

    // transfer ibToken back to caller if not withdraw all
    if (_ibTokenAmountIn > _withdrawnIbTokenAmount) {
      IERC20(_ibToken).safeTransfer(msg.sender, _ibTokenAmountIn - _withdrawnIbTokenAmount);
    }
  }

  /// @dev withdraw ibToken from moneymarket
  /// @param _ibToken The address of ibToken
  /// @param _maxIbTokenToWithdraw Total amount of ibToken sent from moneymarket
  /// @param _requiredUnderlyingAmount The underlying amount needed
  function _withdrawFromMoneyMarket(
    address _ibToken,
    uint256 _maxIbTokenToWithdraw,
    uint256 _requiredUnderlyingAmount
  ) internal returns (uint256 _withdrawnIbTokenAmount, uint256 _withdrawnUnderlyingAmount) {
    uint256 _requiredIbTokenToWithdraw = IInterestBearingToken(_ibToken).convertToShares(_requiredUnderlyingAmount);

    // _maxIbTokenToWithdraw is ibTokenAmount that caller send to strat
    _withdrawnIbTokenAmount = _maxIbTokenToWithdraw > _requiredIbTokenToWithdraw
      ? _requiredIbTokenToWithdraw
      : _maxIbTokenToWithdraw;

    // calling mm.withdraw by specifying that it was withdraw for money market
    // as this is in liquidation process, money market withdraw the ibToken for itself
    _withdrawnUnderlyingAmount = moneyMarket.withdraw(msg.sender, _ibToken, _withdrawnIbTokenAmount);
  }

  /// @dev get required amount of token for swapping
  /// @param _repayAmount The amount needed to repay
  /// @param _path The path for collateralToken to repayToken
  function _getRequiredUnderlyingAmount(
    uint256 _repayAmount,
    address[] memory _path
  ) internal view returns (uint256 _requiredUnderlyingAmount) {
    uint256[] memory amountsIn = router.getAmountsIn(_repayAmount, _path);
    // underlying token amount to swap
    _requiredUnderlyingAmount = amountsIn[0];
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
