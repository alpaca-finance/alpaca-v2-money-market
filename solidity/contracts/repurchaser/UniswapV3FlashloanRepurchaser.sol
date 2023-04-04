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

  address constant UNIV3_FACTORY = 0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7;

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
    address _account,
    uint256 _subAccountId,
    address _debtToken,
    address _underlyingOfCollatToken,
    address _collatToken,
    uint256 _desiredRepayAmount,
    address _poolAddress
  ) external {
    bytes memory data = abi.encode(
      _account,
      _subAccountId,
      _debtToken,
      _underlyingOfCollatToken,
      _collatToken,
      _desiredRepayAmount
    );

    // swap from underlyingOfColalt to debt aka flashloan debt, repurchase and repay underlyingOfCollat
    if (_debtToken < _underlyingOfCollatToken) {
      // debtToken is token0, underlyingOfCollatToken is token1
      IUniswapV3Pool(_poolAddress).swap(
        address(this),
        false, // swap token1 to token0
        -int256(_desiredRepayAmount), // negative means exact output
        1461446703485210103287273052203988822378723970341, // simulate SwapRouter's when `sqrtPriceLimitX96 = 0, zeroForOne = false`
        data
      );
    } else {
      IUniswapV3Pool(_poolAddress).swap(
        address(this),
        true, // swap token0 to token1
        int256(_desiredRepayAmount), // positive means exact input
        4295128740, // simulate SwapRouter's when `sqrtPriceLimitX96 = 0, zeroForOne = true`
        data
      );
    }
  }

  bytes32 internal constant POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

  /// @notice The identifying key of the pool
  struct PoolKey {
    address token0;
    address token1;
    uint24 fee;
  }

  /// @notice Deterministically computes the pool address given the factory and PoolKey
  /// @param factory The Uniswap V3 factory contract address
  /// @param key The PoolKey
  /// @return pool The contract address of the V3 pool
  function computeAddress(address factory, PoolKey memory key) internal pure returns (address pool) {
    require(key.token0 < key.token1);
    pool = address(
      uint160(
        uint256(
          keccak256(
            abi.encodePacked(
              hex"ff",
              factory,
              keccak256(abi.encode(key.token0, key.token1, key.fee)),
              POOL_INIT_CODE_HASH
            )
          )
        )
      )
    );
  }

  /// @notice Returns PoolKey: the ordered tokens with the matched fee levels
  /// @param tokenA The first token of a pool, unsorted
  /// @param tokenB The second token of a pool, unsorted
  /// @param fee The fee level of the pool
  /// @return Poolkey The pool details with ordered token0 and token1 assignments
  function getPoolKey(
    address tokenA,
    address tokenB,
    uint24 fee
  ) internal pure returns (PoolKey memory) {
    if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
    return PoolKey({ token0: tokenA, token1: tokenB, fee: fee });
  }

  function uniswapV3SwapCallback(
    int256 amount0Delta,
    int256 amount1Delta,
    bytes calldata data
  ) external override {
    (
      address _account,
      uint256 _subAccountId,
      address _debtToken,
      address _underlyingOfCollatToken, // underlying of ib collat
      address _collatToken, // ib collat, pass from outside to save gas
      uint256 _desiredRepayAmount
    ) = abi.decode(data, (address, uint256, address, address, address, uint256));

    // verify `msg.sender` is pool
    // TODO: fee tier
    address pool = computeAddress(UNIV3_FACTORY, getPoolKey(_debtToken, _underlyingOfCollatToken, 3000));
    if (msg.sender != pool) revert();

    console.log(IERC20(_debtToken).balanceOf(address(this)));
    console.log(IERC20(_underlyingOfCollatToken).balanceOf(address(this)));

    _repurchaseAndWithdrawIb(_account, _subAccountId, _debtToken, _collatToken, _desiredRepayAmount);

    console.log(IERC20(_debtToken).balanceOf(address(this)));
    console.log(IERC20(_underlyingOfCollatToken).balanceOf(address(this)));

    // repay flashloan on positve amountDelta side. only one can be positive.
    IERC20(_underlyingOfCollatToken).safeTransfer(msg.sender, uint256(amount0Delta > 0 ? amount0Delta : amount1Delta));

    console.log(IERC20(_debtToken).balanceOf(address(this)));
    console.log(IERC20(_underlyingOfCollatToken).balanceOf(address(this)));

    // if (IERC20(_debtToken).balanceOf(address(this)) > 0)
    //   IERC20(_debtToken).transfer(owner, IERC20(_debtToken).balanceOf(address(this)));
    // if (IERC20(_underlyingOfCollatToken).balanceOf(address(this)) > 0)
    //   IERC20(_underlyingOfCollatToken).transfer(owner, IERC20(_underlyingOfCollatToken).balanceOf(address(this)));
  }

  function _repurchaseAndWithdrawIb(
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

  // might be used in future
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
}
