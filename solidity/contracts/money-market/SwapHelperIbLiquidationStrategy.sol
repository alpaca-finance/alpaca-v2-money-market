// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// ---- External Libraries ---- //
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// ---- Libraries ---- //
import { LibSafeToken } from "./libraries/LibSafeToken.sol";

// ---- Interfaces ---- //
import { ILiquidationStrategy } from "./interfaces/ILiquidationStrategy.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { IMoneyMarket } from "./interfaces/IMoneyMarket.sol";
import { ISwapHelper } from "solidity/contracts/interfaces/ISwapHelper.sol";

contract SwapHelperIbLiquidationStrategy is ILiquidationStrategy, Ownable {
  using LibSafeToken for IERC20;

  event LogSetCaller(address _caller, bool _isOk);

  error SwapHelperIbTokenLiquidationStrategy_Unauthorized();
  error SwapHelperIbTokenLiquidationStrategy_RepayTokenIsSameWithUnderlyingToken();
  error SwapHelperIbTokenLiquidationStrategy_SwapFailed();

  ISwapHelper internal immutable swapHelper;
  IMoneyMarket internal immutable moneyMarket;

  mapping(address => bool) public callersOk;

  struct WithdrawParam {
    address to;
    address token;
    uint256 amount;
  }

  /// @notice allow only whitelisted callers
  modifier onlyWhitelistedCallers() {
    if (!callersOk[msg.sender]) {
      revert SwapHelperIbTokenLiquidationStrategy_Unauthorized();
    }
    _;
  }

  constructor(address _swapHelper, address _moneyMarket) {
    swapHelper = ISwapHelper(_swapHelper);
    moneyMarket = IMoneyMarket(_moneyMarket);
  }

  /// @notice Execute liquidate from collatToken to repayToken
  /// @param _ibToken The source token
  /// @param _repayToken The destination token
  /// @param _ibTokenAmountIn Available amount of source token to trade
  /// @param _minReceive Min token receive after swap
  /// @param _data Bridge token address. Direct swap if address(0).
  /// If bridge token == underlying or repay token it will revert because path to same token is not set.
  function executeLiquidation(
    address _ibToken,
    address _repayToken,
    uint256 _ibTokenAmountIn,
    uint256 /*_repayAmount*/,
    uint256 _minReceive,
    bytes memory _data
  ) external onlyWhitelistedCallers {
    // Get underlying tokenAddress from MoneyMarket
    address _underlyingToken = moneyMarket.getTokenFromIbToken(_ibToken);

    // Revert if _underlyingToken and _repayToken are the same address
    if (_underlyingToken == _repayToken) {
      revert SwapHelperIbTokenLiquidationStrategy_RepayTokenIsSameWithUnderlyingToken();
    }

    // Withdraw ibToken from Moneymarket for underlyingToken
    uint256 _withdrawnUnderlyingAmount = moneyMarket.withdraw(msg.sender, _ibToken, _ibTokenAmountIn);

    // Swap underlyingToken to repayToken
    address _bridgeToken = abi.decode(_data, (address));
    if (_bridgeToken != address(0)) {
      // Use bridge token
      _swapExactIn(_underlyingToken, _bridgeToken, _withdrawnUnderlyingAmount, 0, address(this));
      _swapExactIn(_bridgeToken, _repayToken, IERC20(_bridgeToken).balanceOf(address(this)), _minReceive, msg.sender);
    } else {
      // Direct swap
      _swapExactIn(_underlyingToken, _repayToken, _withdrawnUnderlyingAmount, _minReceive, msg.sender);
    }
  }

  function _swapExactIn(
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    uint256 _minReceive,
    address _receiver
  ) internal {
    // Get swap data from swapHelper
    // swap all ib's underlyingToken to repayToken and send to msg.sender
    // NOTE: this only works with swap exact input
    // if swap exact output is used, `underlyingToken` might be stuck here
    (address _router, bytes memory _swapCalldata) = swapHelper.getSwapCalldata(
      _tokenIn,
      _tokenOut,
      _amountIn,
      _receiver,
      _minReceive
    );

    // Approve router for swapping
    IERC20(_tokenIn).safeApprove(_router, _amountIn);
    // Do swap
    (bool _success, ) = _router.call(_swapCalldata);
    // Revert if swap failed
    if (!_success) {
      revert SwapHelperIbTokenLiquidationStrategy_SwapFailed();
    }
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
