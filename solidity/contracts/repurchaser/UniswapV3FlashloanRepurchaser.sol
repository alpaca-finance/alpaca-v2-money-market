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

contract UniswapV3FlashloanRepurchaser is IUniswapV3SwapCallback {
  using LibSafeToken for IERC20;

  error UniswapV3FlashloanRepurchaser_Unauthorized();
  error UniswapV3FlashloanRepurchaser_BadPool();

  address constant UNISWAP_V3_FACTORY = 0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7;
  bytes32 internal constant POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

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

  function withdrawToken(address _token) external {
    if (msg.sender != owner) revert UniswapV3FlashloanRepurchaser_Unauthorized();
    IERC20(_token).safeTransfer(owner, IERC20(_token).balanceOf(address(this)));
  }

  function initRepurchase(bytes calldata data) external {
    (
      ,
      ,
      address _debtToken,
      address _underlyingOfCollatToken,
      ,
      uint24 _fee,
      uint256 _desiredRepayAmount
    ) = _decodeData(data);

    address _poolAddress = _computePoolAddress(_debtToken, _underlyingOfCollatToken, _fee);

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

  function uniswapV3SwapCallback(
    int256 amount0Delta,
    int256 amount1Delta,
    bytes calldata data
  ) external override {
    (
      address _account,
      uint256 _subAccountId,
      address _debtToken,
      address _underlyingOfCollatToken,
      address _collatToken,
      uint24 _flashloanFee,
      uint256 _desiredRepayAmount
    ) = _decodeData(data);

    // verify `msg.sender` is pool
    address pool = _computePoolAddress(_debtToken, _underlyingOfCollatToken, _flashloanFee);
    if (msg.sender != pool) revert UniswapV3FlashloanRepurchaser_BadPool();

    _repurchaseAndWithdrawIb(_account, _subAccountId, _debtToken, _collatToken, _desiredRepayAmount);

    // repay flashloan on positve amountDelta side. only one side can be positive.
    IERC20(_underlyingOfCollatToken).safeTransfer(msg.sender, uint256(amount0Delta > 0 ? amount0Delta : amount1Delta));
    // remaining profit after repay flashloan will remain in this contract until we call `withdrawToken`
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

  function _computePoolAddress(
    address tokenA,
    address tokenB,
    uint24 fee
  ) internal pure returns (address poolAddress) {
    if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
    return
      address(
        uint160(
          uint256(
            keccak256(
              abi.encodePacked(
                hex"ff",
                UNISWAP_V3_FACTORY,
                keccak256(abi.encode(tokenA, tokenB, fee)),
                POOL_INIT_CODE_HASH
              )
            )
          )
        )
      );
  }

  function _decodeData(bytes memory data)
    internal
    pure
    returns (
      address _account,
      uint256 _subAccountId,
      address _debtToken,
      address _underlyingOfCollatToken, // underlying of ib collat
      address _collatToken, // ib collat, pass from outside to save gas
      uint24 _flashloanFee,
      uint256 _desiredRepayAmount
    )
  {
    return abi.decode(data, (address, uint256, address, address, address, uint24, uint256));
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
