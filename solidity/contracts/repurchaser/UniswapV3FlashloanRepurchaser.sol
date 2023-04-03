// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import { IERC20 } from "solidity/contracts/interfaces/IERC20.sol";
import { IMoneyMarket } from "solidity/contracts/money-market/interfaces/IMoneyMarket.sol";
import { IMoneyMarketAccountManager } from "solidity/contracts/interfaces/IMoneyMarketAccountManager.sol";
import { IUniswapV3Pool } from "./interfaces/IUniswapV3Pool.sol";
import { IUniswapV3FlashCallback } from "./interfaces/IUniswapV3FlashCallback.sol";
import { IUniswapV3SwapCallback } from "./interfaces/IUniswapV3SwapCallback.sol";
import { IUniswapV3SwapRouter } from "./interfaces/IUniswapV3SwapRouter.sol";

import { LibSafeToken } from "./libraries/LibSafeToken.sol";

import "solidity/tests/utils/console.sol";

contract UniswapV3FlashloanRepurchaser is IUniswapV3SwapCallback {
  using LibSafeToken for IERC20;

  // TODO: change to constant when deploy
  address public immutable owner;
  IMoneyMarket public immutable moneyMarketDiamond;
  IMoneyMarketAccountManager public immutable accountManager;

  constructor(
    address _owner,
    address _moneyMarketDiamond,
    address _accountManager
  ) {
    owner = _owner;
    moneyMarketDiamond = IMoneyMarket(_moneyMarketDiamond);
    accountManager = IMoneyMarketAccountManager(_accountManager);
  }

  function initRepurchase(
    // address _account,
    // uint256 _subAccountId,
    // address _debtToken,
    // address _underlyingOfCollatToken,
    // address _collatToken,
    uint256 _desiredRepayAmount,
    bytes calldata data,
    address flashPoolAddress
  ) external {
    // IUniswapV3Pool(flashPoolAddress).flash(
    //   address(this),
    //   _debtToken < _underlyingOfCollatToken ? _desiredRepayAmount : 0,
    //   _debtToken < _underlyingOfCollatToken ? 0 : _desiredRepayAmount,
    //   abi.encode(_account, _subAccountId, _debtToken, _underlyingOfCollatToken, _collatToken, _desiredRepayAmount)
    // );
    // IUniswapV3Pool(flashPoolAddress).swap(address(this), true, int256(_desiredRepayAmount), 4295128739 + 1, data);
    IUniswapV3Pool(flashPoolAddress).swap(
      address(this),
      false,
      -int256(_desiredRepayAmount),
      1461446703485210103287273052203988822378723970342 - 1,
      data
    );
  }

  // function uniswapV3FlashCallback(
  //   uint256 fee0,
  //   uint256 fee1,
  //   bytes calldata data
  // ) external override {
  //   (
  //     address _account,
  //     uint256 _subAccountId,
  //     address _debtToken,
  //     address _underlyingOfCollatToken, // underlying of ib collat
  //     address _collatToken, // ib collat, pass from outside to save gas
  //     uint256 _desiredRepayAmount
  //   ) = abi.decode(data, (address, uint256, address, address, address, uint256));

  //   uint256 _debtTokenBalanceBefore = IERC20(_debtToken).balanceOf(address(this));
  //   uint256 _underlyingOfCollatTokenBalanceBefore = IERC20(_underlyingOfCollatToken).balanceOf(address(this));

  //   // repurchase (exchange `debtToken` for `underlyingOfCollatToken`)
  //   _repurchaseIbCollat(_account, _subAccountId, _debtToken, _collatToken, _desiredRepayAmount);

  //   uint256 _debtTokenRepurchased = _debtTokenBalanceBefore - IERC20(_debtToken).balanceOf(address(this));

  //   // swap all `underlyingOfCollatToken` received from repurchasing back to `debtToken`
  //   IUniswapV3SwapRouter.ExactInputSingleParams memory swapParams = IUniswapV3SwapRouter.ExactInputSingleParams({
  //     tokenIn: _underlyingOfCollatToken,
  //     tokenOut: _debtToken,
  //     fee: 3000, // TODO: pick swap fee dynamically
  //     recipient: address(this),
  //     deadline: block.timestamp,
  //     amountIn: IERC20(_underlyingOfCollatToken).balanceOf(address(this)) - _underlyingOfCollatTokenBalanceBefore, // TODO
  //     amountOutMinimum: _debtTokenRepurchased,
  //     sqrtPriceLimitX96: 0 // price agnostic as long as we get min amountOut
  //   });
  //   uniV3SwapRouter.exactInputSingle(swapParams);

  //   IERC20(_debtToken).safeTransfer(msg.sender, _debtToken < _underlyingOfCollatToken ? fee0 : fee1);

  //   // we want to keep `debtToken` in this contract
  //   // when repurchased occured means `debtToken` is up or `collatToken` is down

  //   // flash 100 debt, need to repay 101 debt
  //   // repurchase only 80 debt, get 85 collat, 20 debt remaining
  //   // swap 85 collat for 85 debt (have 105 debt, 0 collat now)
  //   // repay 101 debt, profit 4 debt
  // }

  function _repurchaseIbCollat(
    address _account,
    uint256 _subAccountId,
    address _debtToken,
    address _collatToken,
    uint256 _desiredRepayAmount
  ) internal {
    // approve max and reset because we don't know exact repay amount
    IERC20(_debtToken).safeApprove(address(moneyMarketDiamond), type(uint256).max);
    uint256 _collatTokenReceived = moneyMarketDiamond.repurchase(
      _account,
      _subAccountId,
      _debtToken,
      _collatToken,
      _desiredRepayAmount
    );
    IERC20(_debtToken).safeApprove(address(moneyMarketDiamond), 0);

    // fine to approve exact amount because withdraw will spend it all
    IERC20(_collatToken).safeApprove(address(accountManager), _collatTokenReceived);
    accountManager.withdraw(_collatToken, _collatTokenReceived);
  }

  function uniswapV3SwapCallback(
    int256 amount0Delta,
    int256 amount1Delta,
    bytes calldata data
  ) external override {
    // TODO: validate factory

    console.logInt(amount0Delta);
    console.logInt(amount1Delta);

    (
      address _account,
      uint256 _subAccountId,
      address _debtToken,
      address _underlyingOfCollatToken, // underlying of ib collat
      address _collatToken, // ib collat, pass from outside to save gas
      uint256 _desiredRepayAmount
    ) = abi.decode(data, (address, uint256, address, address, address, uint256));

    console.log(IERC20(_debtToken).balanceOf(address(this)));
    console.log(IERC20(_underlyingOfCollatToken).balanceOf(address(this)));

    _repurchaseIbCollat(_account, _subAccountId, _debtToken, _collatToken, _desiredRepayAmount);

    // repay flashloan. will revert underflow if unprofitable
    IERC20(_underlyingOfCollatToken).safeTransfer(msg.sender, uint256(amount1Delta));
    // remaining profit after repay flashloan will remain in this contract until we call `withdrawToken`
  }
}
